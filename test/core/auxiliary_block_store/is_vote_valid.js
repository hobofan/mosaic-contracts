// Copyright 2018 OpenST Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// ----------------------------------------------------------------------------
//
// http://www.simpletoken.org/
//
// ----------------------------------------------------------------------------

const AuxStoreUtils = require('./helpers/aux_store_utils.js');
const BN = require('bn.js');
const MetaBlock = require('../../test_lib/meta_block.js');

const TestData = require('./helpers/data.js');

const AuxiliaryBlockStore = artifacts.require('AuxiliaryBlockStore');
const BlockStoreMock = artifacts.require('BlockStoreMock');

contract('AuxiliaryBlockStore.isVoteValid()', async (accounts) => {

    let coreIdentifier = '0x0000000000000000000000000000000000000001';
    let epochLength = new BN('3');
    let pollingPlaceAddress = accounts[0];
    let originBlockStore;
    let testBlocks = TestData.blocks;
    let initialBlockHash = TestData.initialBlock.hash;
    let initialStateRoot = TestData.initialBlock.stateRoot;
    let initialGas = TestData.initialBlock.gas;
    let initialTransactionRoot = TestData.initialBlock.transactionRoot;
    let initialHeight = TestData.initialBlock.height;
    let unknownBlockHash = '0x123456f3d32a11c606f8ae8265344d2ab06d71500289df6f9cac2e0139654321';
    let initialKernelHash  = TestData.initialBlock.kernelHash;

    let blockStore;

    beforeEach(async () => {
        originBlockStore = await BlockStoreMock.new();

        blockStore = await AuxiliaryBlockStore.new(
            coreIdentifier,
            epochLength,
            pollingPlaceAddress,
            originBlockStore.address,
            initialBlockHash,
            initialStateRoot,
            initialHeight,
            initialGas,
            initialTransactionRoot,
            initialKernelHash
        );

        await AuxStoreUtils.reportBlocks(blockStore, testBlocks);
    });

    it('should return true for valid votes', async () => {
        await AuxStoreUtils.testValidVotes(
            blockStore,
            coreIdentifier,
            [
                {
                    dynasty: new BN('0'),
                    source: initialBlockHash,
                    target: testBlocks[3].hash,
                    accumulatedGas: initialGas,
                    accumulatedTransactionRoot: initialTransactionRoot,
                },
                {
                    dynasty: new BN('0'),
                    source: initialBlockHash,
                    target: testBlocks[6].hash,
                    accumulatedGas: initialGas,
                    accumulatedTransactionRoot: initialTransactionRoot,
                },
                {
                    dynasty: new BN('0'),
                    source: initialBlockHash,
                    target: testBlocks[9].hash,
                    accumulatedGas: initialGas,
                    accumulatedTransactionRoot: initialTransactionRoot,
                },
                {
                    dynasty: new BN('0'),
                    source: initialBlockHash,
                    target: testBlocks[12].hash,
                    accumulatedGas: initialGas,
                    accumulatedTransactionRoot: initialTransactionRoot,
                },
            ],
        );

        await blockStore.justify(
            initialBlockHash,
            testBlocks[3].hash,
            {from: pollingPlaceAddress},
        );
        await AuxStoreUtils.testValidVotes(
            blockStore,
            coreIdentifier,
            [
                {
                    dynasty: new BN('1'),
                    source: testBlocks[3].hash,
                    target: testBlocks[6].hash,
                    accumulatedGas: testBlocks[3].accumulatedGas,
                    accumulatedTransactionRoot: testBlocks[3].accumulatedTransactionRoot,
                },
                {
                    dynasty: new BN('1'),
                    source: testBlocks[3].hash,
                    target: testBlocks[9].hash,
                    accumulatedGas: testBlocks[3].accumulatedGas,
                    accumulatedTransactionRoot: testBlocks[3].accumulatedTransactionRoot,
                },
                {
                    dynasty: new BN('1'),
                    source: testBlocks[3].hash,
                    target: testBlocks[12].hash,
                    accumulatedGas: testBlocks[3].accumulatedGas,
                    accumulatedTransactionRoot: testBlocks[3].accumulatedTransactionRoot,
                },
            ],
        );

        await blockStore.justify(
            testBlocks[3].hash,
            testBlocks[6].hash,
            {from: pollingPlaceAddress},
        );
        await AuxStoreUtils.testValidVotes(
            blockStore,
            coreIdentifier,
            [
                {
                    dynasty: new BN('2'),
                    source: testBlocks[6].hash,
                    target: testBlocks[9].hash,
                    accumulatedGas: testBlocks[6].accumulatedGas,
                    accumulatedTransactionRoot: testBlocks[6].accumulatedTransactionRoot,
                },
                {
                    dynasty: new BN('2'),
                    source: testBlocks[6].hash,
                    target: testBlocks[12].hash,
                    accumulatedGas: testBlocks[6].accumulatedGas,
                    accumulatedTransactionRoot: testBlocks[6].accumulatedTransactionRoot,
                },
            ],
        );
    });

    it('should not accept an unknown source hash', async () => {
        let transition = {
            coreIdentifier: coreIdentifier,
            kernelHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            auxiliaryDynasty: new BN('1'),
            auxiliaryBlockHash: unknownBlockHash,
            gas: initialGas,
            originDynasty: new BN('0'),
            originBlockHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            transactionRoot: initialTransactionRoot,
        };

        let isValid = await blockStore.isVoteValid.call(
            MetaBlock.hashAuxiliaryTransition(transition),
            unknownBlockHash,
            testBlocks[3].hash,
        );
        assert(
            !isValid,
            'Vote expected to be invalid; instead it was valid.',
        );
    });

    it('should not accept an unknown target hash', async () => {
        let transition = {
            coreIdentifier: coreIdentifier,
            kernelHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            auxiliaryDynasty: new BN('0'),
            auxiliaryBlockHash: initialBlockHash,
            gas: initialGas,
            originDynasty: new BN('0'),
            originBlockHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            transactionRoot: initialTransactionRoot,
        };

        let isValid = await blockStore.isVoteValid.call(
            MetaBlock.hashAuxiliaryTransition(transition),
            initialBlockHash,
            unknownBlockHash,
        );
        assert(
            !isValid,
            'Vote expected to be invalid; instead it was valid.',
        );
    });

    it('should not accept a source checkpoint that is not justified', async () => {
        let transition = {
            coreIdentifier: coreIdentifier,
            kernelHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            auxiliaryDynasty: new BN('1'),
            auxiliaryBlockHash: testBlocks[3].hash,
            gas: testBlocks[3].accumulatedGas,
            originDynasty: new BN('0'),
            originBlockHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            transactionRoot: testBlocks[3].accumulatedTransactionRoot,
        };

        let isValid = await blockStore.isVoteValid.call(
            MetaBlock.hashAuxiliaryTransition(transition),
            testBlocks[3].hash,
            testBlocks[6].hash,
        );
        assert(
            !isValid,
            'Vote expected to be invalid; instead it was valid.',
        );
    });

    it( 'should not accept a target block that has a height that is not a ' +
        'multiple of the epoch length',
        async () => {
            let transition = {
                coreIdentifier: coreIdentifier,
                kernelHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
                auxiliaryDynasty: new BN('0'),
                auxiliaryBlockHash: initialBlockHash,
                gas: initialGas,
                originDynasty: new BN('0'),
                originBlockHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
                transactionRoot: initialTransactionRoot,
            };

            let isValid = await blockStore.isVoteValid.call(
                MetaBlock.hashAuxiliaryTransition(transition),
                initialBlockHash,
                testBlocks[4].hash,
            );
            assert(
                !isValid,
                'Vote expected to be invalid; instead it was valid.',
            );
        }
    );

    it('should not accept a target block that has a height lower than the head', async () => {
        await blockStore.justify(
            initialBlockHash,
            testBlocks[3].hash,
            {from: pollingPlaceAddress},
        );
        await blockStore.justify(
            testBlocks[3].hash,
            testBlocks[6].hash,
            {from: pollingPlaceAddress},
        );
        await blockStore.justify(
            testBlocks[6].hash,
            testBlocks[9].hash,
            {from: pollingPlaceAddress},
        );

        let transition = {
            coreIdentifier: coreIdentifier,
            kernelHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            auxiliaryDynasty: new BN('1'),
            auxiliaryBlockHash: testBlocks[3].hash,
            gas: testBlocks[3].accumulatedGas,
            originDynasty: new BN('0'),
            originBlockHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            transactionRoot: testBlocks[3].accumulatedTransactionRoot,
        };

        let isValid = await blockStore.isVoteValid.call(
            MetaBlock.hashAuxiliaryTransition(transition),
            testBlocks[3].hash,
            testBlocks[6].hash,
        );
        assert(
            !isValid,
            'Vote expected to be invalid; instead it was valid.',
        );
    });

    it('should not accept an invalid transition hash', async () => {
        let transition = {
            coreIdentifier: coreIdentifier,
            kernelHash: '0x1234560000000000000000000000000000000000000000000000000000000000',
            auxiliaryDynasty: new BN('0'),
            auxiliaryBlockHash: initialBlockHash,
            gas: initialGas,
            originDynasty: new BN('0'),
            originBlockHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            transactionRoot: initialTransactionRoot,
        };

        let isValid = await blockStore.isVoteValid.call(
            MetaBlock.hashAuxiliaryTransition(transition),
            initialBlockHash,
            testBlocks[3].hash,
        );
        assert(
            !isValid,
            'Vote expected to be invalid; instead it was valid.',
        );
    });

    it('should not allow the target to be below the source', async () => {
        await blockStore.justify(
            initialBlockHash,
            testBlocks[6].hash,
            {from: pollingPlaceAddress},
        );
        let transition = {
            coreIdentifier: coreIdentifier,
            kernelHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            auxiliaryDynasty: new BN('1'),
            auxiliaryBlockHash: testBlocks[6].hash,
            gas: testBlocks[6].accumulatedGas,
            originDynasty: new BN('0'),
            originBlockHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            transactionRoot: testBlocks[6].accumulatedTransactionRoot,
        };

        let isValid = await blockStore.isVoteValid.call(
            MetaBlock.hashAuxiliaryTransition(transition),
            testBlocks[6].hash,
            testBlocks[3].hash,
        );
        assert(
            !isValid,
            'Vote expected to be invalid; instead it was valid.',
        );
    });

    it('should not allow the target to be justified with a different source', async () => {
        await blockStore.justify(
            initialBlockHash,
            testBlocks[3].hash,
            {from: pollingPlaceAddress},
        );
        await blockStore.justify(
            testBlocks[3].hash,
            testBlocks[6].hash,
            {from: pollingPlaceAddress},
        );
        await blockStore.justify(
            testBlocks[3].hash,
            testBlocks[9].hash,
            {from: pollingPlaceAddress},
        );

        let transition = {
            coreIdentifier: coreIdentifier,
            kernelHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            auxiliaryDynasty: new BN('2'),
            auxiliaryBlockHash: testBlocks[6].hash,
            gas: testBlocks[6].accumulatedGas,
            originDynasty: new BN('0'),
            originBlockHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            transactionRoot: testBlocks[6].accumulatedTransactionRoot,
        };

        let isValid = await blockStore.isVoteValid.call(
            MetaBlock.hashAuxiliaryTransition(transition),
            testBlocks[6].hash,
            testBlocks[9].hash,
        );
        assert(
            !isValid,
            'Vote expected to be invalid; instead it was valid.',
        );
    });

    it('should not allow the target to not be a descendant of the source', async () => {
        // The fork blocks have a different transaction root (and thus hash).
        let forkBlocks = {
            1: {
                header: '0xf901f9a07f1034f3d32a11c606f8ae8265344d2ab06d71500289df6f9cac2e013990830ca01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347948888f1f195afa192cfee860698584c030f4c9db1a0ef1552a40b7165c3cd773806b9e0c165b75356e0314bf0706f279c729f51e017a06fe50b260da6308036625b850b5d6ced6d0a9f814c0688bc91ffb7b7a3a54b67a0bc37d79753ad738a6dac4921e57392f145d8887476de3f783dfa7edae9283e52b90100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008302000001832fefd8825208845506eb0780a0bd4472abb6659ebe3ee06ee4d7b72a00a9f4d001caca51342001075469aff49888a13a5a8c8f2bb1c4',
                hash: '0x168032d5593d56e2b392a6233b9fd3282b5544950a38c127266321b406c056ff',
            },
            2: {
                header: '0xf901f9a0168032d5593d56e2b392a6233b9fd3282b5544950a38c127266321b406c056ffa01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347948888f1f195afa192cfee860698584c030f4c9db1a0ef1552a40b7165c3cd773806b9e0c165b75356e0314bf0706f279c729f51e017a06fe50b260da6308036625b850b5d6ced6d0a9f814c0688bc91ffb7b7a3a54b67a0bc37d79753ad738a6dac4921e57392f145d8887476de3f783dfa7edae9283e52b90100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008302000002832fefd8825208845506eb0780a0bd4472abb6659ebe3ee06ee4d7b72a00a9f4d001caca51342001075469aff49888a13a5a8c8f2bb1c4',
                hash: '0x18b5efebac8e5d3344858fc4130d9349b986a5de11b8e4527f69b2eb62bc2578',
            },
            3: {
                header: '0xf901f9a018b5efebac8e5d3344858fc4130d9349b986a5de11b8e4527f69b2eb62bc2578a01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347948888f1f195afa192cfee860698584c030f4c9db1a0ef1552a40b7165c3cd773806b9e0c165b75356e0314bf0706f279c729f51e017a06fe50b260da6308036625b850b5d6ced6d0a9f814c0688bc91ffb7b7a3a54b67a0bc37d79753ad738a6dac4921e57392f145d8887476de3f783dfa7edae9283e52b90100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008302000003832fefd8825208845506eb0780a0bd4472abb6659ebe3ee06ee4d7b72a00a9f4d001caca51342001075469aff49888a13a5a8c8f2bb1c4',
                hash: '0x2b626bb13bb77d56dc39a7e8d8fa13c00be2d9332a738dc57796762541981a8a',
            },
            4: {
                header: '0xf901f9a02b626bb13bb77d56dc39a7e8d8fa13c00be2d9332a738dc57796762541981a8aa01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347948888f1f195afa192cfee860698584c030f4c9db1a0ef1552a40b7165c3cd773806b9e0c165b75356e0314bf0706f279c729f51e017a06fe50b260da6308036625b850b5d6ced6d0a9f814c0688bc91ffb7b7a3a54b67a0bc37d79753ad738a6dac4921e57392f145d8887476de3f783dfa7edae9283e52b90100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008302000004832fefd8825208845506eb0780a0bd4472abb6659ebe3ee06ee4d7b72a00a9f4d001caca51342001075469aff49888a13a5a8c8f2bb1c4',
                hash: '0x685adb72bd64e87d7aaae0a39585bc80832be03a6922de3bbd96045841cf5c7b',
            },
            5: {
                header: '0xf901f9a0685adb72bd64e87d7aaae0a39585bc80832be03a6922de3bbd96045841cf5c7ba01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347948888f1f195afa192cfee860698584c030f4c9db1a0ef1552a40b7165c3cd773806b9e0c165b75356e0314bf0706f279c729f51e017a06fe50b260da6308036625b850b5d6ced6d0a9f814c0688bc91ffb7b7a3a54b67a0bc37d79753ad738a6dac4921e57392f145d8887476de3f783dfa7edae9283e52b90100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008302000005832fefd8825208845506eb0780a0bd4472abb6659ebe3ee06ee4d7b72a00a9f4d001caca51342001075469aff49888a13a5a8c8f2bb1c4',
                hash: '0x34c1e15f82e43dab8fdefabfb232cbbc812a0bc9cc0d3e4dd4a4457a3bdbc677',
            },
            6: {
                header: '0xf901f9a034c1e15f82e43dab8fdefabfb232cbbc812a0bc9cc0d3e4dd4a4457a3bdbc677a01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347948888f1f195afa192cfee860698584c030f4c9db1a0ef1552a40b7165c3cd773806b9e0c165b75356e0314bf0706f279c729f51e017a06fe50b260da6308036625b850b5d6ced6d0a9f814c0688bc91ffb7b7a3a54b67a0bc37d79753ad738a6dac4921e57392f145d8887476de3f783dfa7edae9283e52b90100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008302000006832fefd8825208845506eb0780a0bd4472abb6659ebe3ee06ee4d7b72a00a9f4d001caca51342001075469aff49888a13a5a8c8f2bb1c4',
                hash: '0x2f859242c8af9a91c2bd759aded6802e7e769225a9c3a55f9908f8770d46b090',
            },
        };
        await AuxStoreUtils.reportBlocks(blockStore, forkBlocks);

        /*
         * Assert that the alternative fork would be valid before the original
         * fork gets justified.
         */
        await AuxStoreUtils.testValidVotes(
            blockStore,
            coreIdentifier,
            [
                {
                    dynasty: new BN('0'),
                    source: initialBlockHash,
                    target: testBlocks[3].hash,
                    accumulatedGas: initialGas,
                    accumulatedTransactionRoot: initialTransactionRoot,
                },
                {
                    dynasty: new BN('0'),
                    source: initialBlockHash,
                    target: testBlocks[6].hash,
                    accumulatedGas: initialGas,
                    accumulatedTransactionRoot: initialTransactionRoot,
                },
            ],
        );

        /*
         * Justifying on the original fork and then jumping to the alternative
         * fork to check for validity of a vote.
         */
        await blockStore.justify(
            initialBlockHash,
            testBlocks[3].hash,
            {from: pollingPlaceAddress},
        );
        let transition = {
            coreIdentifier: coreIdentifier,
            kernelHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            auxiliaryDynasty: new BN('1'),
            auxiliaryBlockHash: testBlocks[3].hash,
            gas: testBlocks[3].accumulatedGas,
            originDynasty: new BN('0'),
            originBlockHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
            transactionRoot: testBlocks[3].accumulatedTransactionRoot,
        };

        let isValid = await blockStore.isVoteValid.call(
            MetaBlock.hashAuxiliaryTransition(transition),
            testBlocks[3].hash,
            forkBlocks[6].hash,
        );
        assert(
            !isValid,
            'Vote expected to be invalid; instead it was valid.',
        );
    });

});
