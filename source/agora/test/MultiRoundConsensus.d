/*******************************************************************************

    Tests for reaching consensus in multiple rounds instead of 1 round.
    In this test, we make nodes reject nominations for several rounds
    deliberately until one is accepted at a round R, where R could be arbitrarily
    high.

    Copyright:
        Copyright (c) 2020 BOS Platform Foundation Korea
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.MultiRoundConsensus;

version (unittest):

import agora.api.Validator;
import agora.common.Config;
import agora.common.Task;
import agora.consensus.data.Block;
import agora.consensus.data.ConsensusParams;
import agora.consensus.protocol.Nominator;
import agora.common.crypto.Key;
import agora.common.Hash;
import agora.consensus.data.Transaction;
import agora.consensus.data.genesis.Test;
import agora.network.NetworkManager;
import agora.node.Ledger;
import agora.test.Base;

import core.stdc.inttypes;
import core.stdc.time;
import core.thread;

import geod24.Registry;

import scpd.types.Stellar_types;
import scpd.types.Stellar_SCP;

/// ditto
unittest
{
    static class CustomNominator : TestNominator
    {
        // To see how many voting rounds are needed to reach consensus
        public static shared int round_number;

        /// Ctor
        public this (NetworkManager network, KeyPair key_pair, Ledger ledger,
            TaskManager taskman, ulong txs_to_nominate)
        {
            super(network, key_pair, ledger, taskman,
                txs_to_nominate);
        }

    extern (C++):
        ///
        public override uint64_t computeHashNode (uint64_t slot_idx,
            ref const(Value) prev, bool is_priority, int32_t round_num,
            ref const(NodeID) node_id) nothrow
        {
            scope(failure) assert(0);
            writeln("round number: ", round_num);
            this.round_number = round_num;
            return super.computeHashNode(slot_idx, prev, is_priority,
                round_num, node_id);
        }
    }

    static class CustomValidator : TestValidatorNode
    {
        /// Ctor
        public this (Config config, Registry* reg, immutable(Block)[] blocks,
                     ulong txs_to_nominate)
        {
            super(config, reg, blocks, txs_to_nominate);
        }

        ///
        protected override CustomNominator getNominator (
            NetworkManager network, KeyPair key_pair, Ledger ledger,
            TaskManager taskman)
        {
            return new CustomNominator(
                network, key_pair, ledger, taskman,
                this.txs_to_nominate);
        }
    }

    static class CustomAPIManager : TestAPIManager
    {
        ///
        public this (immutable(Block)[] blocks, TestConf test_conf)
        {
            super(blocks, test_conf);
        }

        /// set base class
        public override void createNewNode (Config conf, string file, int line)
        {
            if (this.nodes.length == 0)
            {
                auto api = RemoteAPI!TestAPI.spawn!CustomValidator(
                    conf, &this.reg, this.blocks, this.test_conf.txs_to_nominate,
                    conf.node.timeout);
                this.reg.register(conf.node.address, api.tid());
                this.nodes ~= NodePair(conf.node.address, api);
            }
            else
                super.createNewNode(conf, file, line);
        }
    }

    TestConf conf = {
        timeout : 10.seconds,
        validators : 3,
        validator_cycle : 10,
        quorum_threshold : 66
    };

    auto network = makeTestNetwork!CustomAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();
    auto nodes = network.clients;
    auto validator = network.clients[0];

    // Make two of three validators disable to respond
    nodes[1].ctrl.sleep(20.seconds, true);
    nodes[2].ctrl.sleep(20.seconds, true);

    // Block 1 with multiple consensus rounds
    auto txs = genesisSpendable().map!(txb => txb.sign()).array();
    txs.each!(tx => validator.putTransaction(tx));

    Thread.sleep(20.seconds);

    network.expectBlock(Height(1), 5.seconds);
    writeln("Consensus round: ", CustomNominator.round_number);
    //assert(CustomNominator.round_number > 3,
    //    format("The validator's round number: %s. Expected: above %s",
    //        CustomNominator.round_number, 3));

    //// Block 2 externalized within a single round
    //txs = txs.map!(tx => TxBuilder(tx).sign()).array();
    //txs.each!(tx => validator.putTransaction(tx));
    //network.expectBlock(Height(2), 5.seconds);
    //assert(CustomNominator.round_number == 1,
    //    format("The validator's round number: %s. Expected: %s",
    //        CustomNominator.round_number, 1));
}
