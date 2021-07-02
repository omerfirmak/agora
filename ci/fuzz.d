#!/usr/bin/env rdmd
module fuzzer;

private:

import std.algorithm;
import std.file;
import std.format;
import std.path;
import std.process;
import std.stdio;
import std.conv;
import core.sys.posix.signal;
import core.thread;
import core.time;

/// Root of the repository
immutable RootPath = __FILE_FULL_PATH__.dirName.dirName;
immutable IntegrationPath = RootPath.buildPath("tests").buildPath("system");
// Can't use `--project-directory` because it is completely broken:
// https://github.com/docker/compose/issues/6310
immutable ComposeFile = IntegrationPath.buildPath("docker-compose.yml");
immutable EnvFile = IntegrationPath.buildPath("environment.sh");

/+ ***************************** Commands to run **************************** +/
/// A simple test to ensure that the container works correctly,
/// e.g. all dependencies are installed and the binary isn't corrupt.
immutable BuildImg = [ "docker", "build", "--build-arg", `DUB_OPTIONS=-b cov`,
                       "-t", "agora", RootPath, ];
immutable TestContainer = [ "docker", "run", "agora", "--help", ];
immutable DockerCompose = [ "docker-compose", "-f", ComposeFile, "--env-file", EnvFile ];
immutable DockerComposeUp = DockerCompose ~ [ "up", "--abort-on-container-exit", ];
immutable DockerComposeUpNoRecord = DockerComposeUp ~ ["--scale", "har-recorder=0", ];
immutable DockerComposeDown = DockerCompose ~ [ "down", "-t", "30", ];
immutable DockerComposeLogs = DockerCompose ~ [ "logs", "-t", ];
immutable Cleanup = [ "sudo", "rm", "-rf", IntegrationPath.buildPath("node/0/.cache/"),
                      IntegrationPath.buildPath("node/2/.cache/"),
                      IntegrationPath.buildPath("node/3/.cache/"),
                      IntegrationPath.buildPath("node/4/.cache/"),
                      IntegrationPath.buildPath("node/5/.cache/"),
                      IntegrationPath.buildPath("node/6/.cache/"),
                      IntegrationPath.buildPath("node/7/.cache/"),
];

private int main (string[] args)
{
    // Use a recognizable value so that if an unexpected code path is taken,
    // we see it. Success sets this to 0, failure to 1.x
    int code = 42;

    // Need atleast the duration arg
    if (args.length < 2)
    {
        writeln("Fuzzing duration (in minutes) should be passed as the last argument");
        return 1;
    }   
    // last arg should be the duration
    bool record_har = args[$-1] == "record";
    uint duration;
    if (!record_har)
        duration = to!uint(args[$-1]);

    // If the user pass `nobuild` as first argument, skip docker image build,
    // which is the most expensive operation this script performs
    if (args.length < 2 || args[1] != "nobuild")
        runCmd(BuildImg);

    // Simple sanity test
    runCmd(TestContainer);

    // First make sure that there we start from a clean slate,
    // as the docker-compose bind volumes
    runCmd(Cleanup);

    // We need to have a "foreground" process to use `--abort-on-container-exit`
    // This option allows us to detect when the node stops / crash even before
    // the test starts (or after it completes).
    // So we start this process with `spawnProcess` and kill it with SIGINT,
    // simulating a CTRL+C
    auto DockerComposeUpCmd = record_har ? DockerComposeUp : DockerComposeUpNoRecord;
    writeln(DockerComposeUpCmd);
    auto upPid = spawnProcess(DockerComposeUpCmd);

    if (!record_har)
    {
        writefln("Fuzzing for %d minutes..", duration);
        Thread.sleep(dur!"minutes"(duration));
        upPid.kill(SIGINT);
    }

    code = 0;
    if (auto upCode = upPid.wait())
    {
        writeln("docker-compose up returned error code: ", upCode);
        code = 1;
    }
    runCmd(DockerComposeDown);
    return code;
}

/// Utility function to run a command and throw on error
private void runCmd (const string[] cmd)
{
    writeln(cmd);
    auto pid = spawnProcess(cmd);
    if (pid.wait() != 0)
        throw new Exception(format("Command failed: %s", cmd));
}

/// Utility function
private int errorOut (ProcessPipes pp)
{
    pp.stderr.byLine.each!(a => writeln("[fatal]\t", a));
    return 1;
}
