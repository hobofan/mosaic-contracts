pragma solidity ^0.4.23;

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
// Origin Chain: Gateway Contract
//
// http://www.simpletoken.org/
//
// ----------------------------------------------------------------------------


/*

           Origin chain      |       Auxiliary chain
-------------------------------------------------------------------------------
           EIP20Gateway - - - - - - - - - - - EIP20CoGateway
-------------------------------------------------------------------------------

1. Staking and Minting: Normal flow

           stake             --->   confirmStakingIntent
             |
    progressStaking (HL)     --->   progressMinting (HL)
-------------------------------------------------------------------------------
2. Staking and Minting (Revert): Normal flow

           stake             --->   confirmStakingIntent
             |
        revertStake          --->   confirmRevertStakingIntent
                                            |
    progressRevertStaking    <---   progressRevertStaking
-------------------------------------------------------------------------------
3. Staking and Minting: Incase the facilitator is not able to progress

    stake (by facilitator)    --->   confirmStakingIntent (by facilitator)
                               |
                        facilitator (offline)
             |
   progressStakingWithProof   --->   progressMintingWithProof
-------------------------------------------------------------------------------
*/

import "./SimpleStake.sol";
import "./Gateway.sol";

/**
 * @title EIP20Gateway Contract
 *
 * @notice EIP20Gateway act as medium to send messages from origin chain to
 *         auxiliary chain. Currently gateway supports stake and mint , revert
 *         stake message & linking of EIP20Gateway and EIP20CoGateway.
 */
contract EIP20Gateway is Gateway {

    /* Events */

    /** Emitted whenever a staking process is initiated. */
    event StakingIntentDeclared(
        bytes32 indexed _messageHash,
        address _staker,
        uint256 _stakerNonce,
        address _beneficiary,
        uint256 _amount
    );

    /** Emitted whenever a staking is completed. */
    event ProgressedStake(
        bytes32 indexed _messageHash,
        address _staker,
        uint256 _stakerNonce,
        uint256 _amount,
        bool _proofProgress,
        bytes32 _unlockSecret
    );

    /** Emitted whenever a process is initiated to revert staking. */
    event RevertStakeIntentDeclared(
        bytes32 indexed _messageHash,
        address _staker,
        uint256 _stakerNonce,
        uint256 _amount
    );

    /** Emitted whenever a staking is reverted. */
    event RevertedStake(
        bytes32 indexed _messageHash,
        address _staker,
        uint256 _stakerNonce,
        uint256 _amount
    );

    /** Emitted whenever a redemption intent is confirmed. */
    event RedemptionIntentConfirmed(
        bytes32 indexed _messageHash,
        address _redeemer,
        uint256 _redeemerNonce,
        address _beneficiary,
        uint256 _amount,
        uint256 _blockHeight,
        bytes32 _hashLock
    );

    /** Emitted whenever a unstake process is complete. */
    event ProgressedUnstake(
        bytes32 indexed _messageHash,
        address _redeemer,
        address _beneficiary,
        uint256 _redeemAmount,
        uint256 _unstakeAmount,
        uint256 _rewardAmount,
        bool _proofProgress,
        bytes32 _unlockSecret
    );

    /** Emitted whenever a revert redemption intent is confirmed. */
    event RevertRedemptionIntentConfirmed(
        bytes32 indexed _messageHash,
        address _redeemer,
        uint256 _redeemerNonce,
        uint256 _amount
    );

    /** Emitted whenever revert redemption is completed. */
    event RevertRedemptionComplete(
        bytes32 indexed _messageHash,
        address _redeemer,
        uint256 _redeemerNonce,
        uint256 _amount
    );

    /* Struct */

    /**
     * Stake stores the staking information about the staking amount,
     * beneficiary address, message data and facilitator address.
     */
    struct Stake {

        /** Amount that will be staked. */
        uint256 amount;

        /**
         * Address where the utility tokens will be minted in the
         * auxiliary chain.
         */
        address beneficiary;

        /** Address of the facilitator that initiates the staking process. */
        address facilitator;

        /** Bounty kept by facilitator for stake message transfer*/
        uint256 bounty;
    }

    /**
     * Unstake stores the unstaking / redeem information
     * like unstake/redeem amount, beneficiary address, message data.
     */
    struct Unstake {

        /** Amount that will be unstaked. */
        uint256 amount;

        /** Address that will receive the unstaked token */
        address beneficiary;
    }

    /* public variables */

    /** Escrow address to lock staked fund. */
    SimpleStake public stakeVault;


    /** Maps messageHash to the Stake object. */
    mapping(bytes32 /*messageHash*/ => Stake) stakes;

    /** Maps messageHash to the Unstake object. */
    mapping(bytes32 /*messageHash*/ => Unstake) unstakes;

    /* Constructor */

    /**
     * @notice Initialise the contract by providing the ERC20 token address
     *         for which the gateway will enable facilitation of staking and
     *         minting.
     *
     * @param _token The ERC20 token contract address that will be
     *               staked and corresponding utility tokens will be minted
     *               in auxiliary chain.
     * @param _baseToken The ERC20 token address that will be used for
     *                     staking bounty from the facilitators.
     * @param _core Core contract address.
     * @param _bounty The amount that facilitator will stakes to initiate the
     *                staking process.
     * @param _organisation Organisation address.
     */
    constructor(
        EIP20Interface _token,
        EIP20Interface _baseToken,
        CoreInterface _core,
        uint256 _bounty,
        address _organisation,
        address _messageBus
    )
        Gateway(
            _token,
            _baseToken,
            _core,
            _bounty,
            _organisation,
            _messageBus
        )
        public
    {
        // deploy simpleStake contract that will keep the staked amounts.
        stakeVault = new SimpleStake(_token, address(this));
    }

    /* External functions */

    /**
     * @notice Initiates the stake process.
     *
     * @dev In order to stake the staker needs to approve Gateway contract for
     *      stake amount. Staked amount is transferred from staker address to
     *      Gateway contract.
     *
     * @param _amount Staking amount that will be transferred form staker
     *                account.
     * @param _beneficiary The address in the auxiliary chain where the utility
     *                     tokens will be minted.
     * @param _staker Staker address.
     * @param _gasPrice Gas price that staker is ready to pay to get the stake
     *                  and mint process done
     * @param _gasLimit Gas limit that staker is ready to pay
     * @param _nonce Nonce of the staker address.
     * @param _hashLock Hash Lock provided by the facilitator.
     * @param _signature Signature signed by staker.
     *
     * @return messageHash_ which is unique for each request.
     */
    function stake(
        uint256 _amount,
        address _beneficiary,
        address _staker,
        uint256 _gasPrice,
        uint256 _gasLimit,
        uint256 _nonce,
        bytes32 _hashLock,
        bytes _signature
    )
        public
        isActive
        returns (bytes32 messageHash_)
    {
        require(
            _amount > uint256(0),
            "Stake amount must not be zero"
        );
        require(
            _beneficiary != address(0),
            "Beneficiary address must not be zero"
        );
        require(
            _staker != address(0),
            "Staker address must not be zero"
        );
        require(
            _gasPrice != 0,
            "Gas price must not be zero"
        );
        require(
            _gasLimit != 0,
            "Gas limit must not be zero"
        );
        require(
            _signature.length == 65,
            "Signature must be of length 65"
        );

        // Get the staking intent hash
        bytes32 intentHash = GatewayLib.hashStakingIntent(
            _amount,
            _beneficiary,
            _staker,
            _nonce,
            _gasPrice,
            _gasLimit,
            token
        );

        // Get the messageHash
        messageHash_ = MessageBus.messageDigest(
            STAKE_TYPEHASH,
            intentHash,
            _nonce,
            _gasPrice,
            _gasLimit
        );

        // Get previousMessageHash
        bytes32 previousMessageHash = registerOutboxProcess(
            _staker,
            _nonce,
            messageHash_
        );

        // Delete the previous progressed/Revoked stake data
        delete stakes[previousMessageHash];

        // New stake object
        stakes[messageHash_] = Stake({
            amount : _amount,
            beneficiary : _beneficiary,
            facilitator : msg.sender,
            bounty : bounty
            });

        // New message object
        messages[messageHash_] = getMessage(
            _staker,
            _nonce,
            _gasPrice,
            _gasLimit,
            intentHash,
            _hashLock);

        // Declare message in outbox
        MessageBus.declareMessage(
            messageBox,
            STAKE_TYPEHASH,
            messages[messageHash_],
            _signature
        );

        //transfer staker amount to gateway
        require(
            token.transferFrom(_staker, address(this), _amount),
            "Stake amount must be transferred to gateway"
        );

        // transfer the bounty amount
        require(
            baseToken.transferFrom(msg.sender, address(this), bounty),
            "Bounty amount must be transferred to gateway"
        );

        // Emit StakingIntentDeclared event
        emit StakingIntentDeclared(
            messageHash_,
            _staker,
            _nonce,
            _beneficiary,
            _amount
        );
    }

    /**
     * @notice Completes the stake process.
     *
     * @param _messageHash Message hash.
     * @param _unlockSecret Unlock secret for the hashLock provide by the
     *                      facilitator while initiating the stake
     *
     * @return staker_ Staker address
     * @return stakeAmount_ Stake amount
     */
    function progressStaking(
        bytes32 _messageHash,
        bytes32 _unlockSecret
    )
        external
        returns (
            address staker_,
            uint256 stakeAmount_
        )
    {
        require(
            _messageHash != bytes32(0),
            "Message hash must not be zero"
        );
        // Get the message object
        MessageBus.Message storage message;

        (staker_, stakeAmount_, message) = progressStakingInternal(
            _messageHash,
            _unlockSecret,
            false
        );
        // Progress outbox
        MessageBus.progressOutbox(
            messageBox,
            STAKE_TYPEHASH,
            message,
            _unlockSecret
        );
    }

    /**
     * @notice Completes the stake process by providing the merkle proof
     *         instead of unlockSecret. In case the facilitator process is not
     *         able to complete the stake and mint process then this is an
     *         alternative approach to complete the process
     *
     * @dev This can be called to prove that the inbox status of messageBox on
     *      CoGateway is either declared or progressed.
     *
     * @param _messageHash Message hash.
     * @param _rlpEncodedParentNodes RLP encoded parent node data to prove in
     *                               messageBox outbox of CoGateway
     * @param _blockHeight Block number for which the proof is valid
     * @param _messageStatus Message status i.e. Declared or Progressed that
     *                       will be proved.
     *
     * @return staker_ Staker address
     * @return stakeAmount_ Stake amount
     */
    function progressStakingWithProof(
        bytes32 _messageHash,
        bytes _rlpEncodedParentNodes,
        uint256 _blockHeight,
        uint256 _messageStatus
    )
        external
        returns (
            address staker_,
            uint256 stakeAmount_
        )
    {
        require(
            _messageHash != bytes32(0),
            "Message hash must not be zero"
        );
        require(
            _rlpEncodedParentNodes.length > 0,
            "RLP encoded parent nodes must not be zero"
        );

        bytes32 storageRoot = storageRoots[_blockHeight];

        require(
            storageRoot != bytes32(0),
            "Storage root must not be zero"
        );
        MessageBus.Message storage message;

        (staker_, stakeAmount_, message) = progressStakingInternal(
            _messageHash,
            bytes32(0),
            true
        );

        MessageBus.progressOutboxWithProof(
            messageBox,
            STAKE_TYPEHASH,
            message,
            _rlpEncodedParentNodes,
            MESSAGE_BOX_OFFSET,
            storageRoot,
            MessageBus.MessageStatus(_messageStatus)
        );
    }

    /**
     * @notice Revert staking to stop the staking process and get the stake
     *         amount back. Only staker can revert staking by providing
     *         penalty i.e. 1.5 times of bounty. On revert process
     *         penalty and facilitator bounty will be burned.
     *
     * @dev To revert the the sender must sign the sha3(messageHash, nonce+1)
     *
     * @param _messageHash Message hash.
     *
     * @return staker_ Staker address
     * @return stakerNonce_ Staker nonce
     * @return amount_ Stake amount
     */
    function revertStaking(
        bytes32 _messageHash
    )
        external
        returns (
            address staker_,
            uint256 stakerNonce_,
            uint256 amount_
        )
    {
        require(
            _messageHash != bytes32(0),
            "Message hash must not be zero"
        );

        // get the message object for the _messageHash
        MessageBus.Message storage message = messages[_messageHash];

        require(message.sender == msg.sender, "Only staker can revert staking.");

        require(
            message.intentHash != bytes32(0),
            "StakingIntentHash must not be zero"
        );

        // Declare staking revocation.
        MessageBus.declareRevocationMessage(
            messageBox,
            STAKE_TYPEHASH,
            message
        );

        staker_ = message.sender;
        stakerNonce_ = message.nonce;
        amount_ = stakes[_messageHash].amount;

        //penalty charged to staker for revert staking
        uint256 penalty = stakes[_messageHash].bounty
        .mul(REVOCATION_PENALTY)
        .div(100);

        // transfer the penalty amount
        require(baseToken.transferFrom(msg.sender, address(this), penalty));


        // Emit RevertStakeIntentDeclared event.
        emit RevertStakeIntentDeclared(
            _messageHash,
            staker_,
            stakerNonce_,
            amount_
        );
    }

    /**
     * @notice Complete revert staking by providing the merkle proof.
     *         This method will return stake amount to staker and burn
     *         facilitator bounty and staker penalty.
     *
     * @param _messageHash Message hash.
     * @param _blockHeight Block number for which the proof is valid
     * @param _rlpEncodedParentNodes RLP encoded parent node data to prove
     *                               DeclaredRevocation in messageBox inbox
     *                               of CoGateway
     *
     * @return staker_ Staker address
     * @return stakerNonce_ Staker nonce
     * @return amount_ Stake amount
     */
    function progressRevertStaking(
        bytes32 _messageHash,
        uint256 _blockHeight,
        bytes _rlpEncodedParentNodes
    )
        external
        returns (
            address staker_,
            uint256 stakerNonce_,
            uint256 amount_
    )
    {
        require(
            _messageHash != bytes32(0),
            "Message hash must not be zero"
        );
        require(
            _rlpEncodedParentNodes.length > 0,
            "RLP encoded parent nodes must not be zero"
        );

        // Get the message object
        MessageBus.Message storage message = messages[_messageHash];
        require(
            message.intentHash != bytes32(0),
            "StakingIntentHash must not be zero"
        );

        // Get the storageRoot for the given block height
        bytes32 storageRoot = storageRoots[_blockHeight];
        require(
            storageRoot != bytes32(0),
            "Storage root must not be zero"
        );

        // Progress with revocation message
        MessageBus.progressOutboxRevocation(
            messageBox,
            message,
            STAKE_TYPEHASH,
            MESSAGE_BOX_OFFSET,
            _rlpEncodedParentNodes,
            storageRoot,
            MessageBus.MessageStatus.Revoked
        );

        staker_ = message.sender;
        stakerNonce_ = message.nonce;
        amount_ = stakes[_messageHash].amount;

        // transfer the staked amount to the staker
        token.transfer(message.sender, amount_);

        // burn facilitator bounty
        baseToken.transfer(address(0), bounty);
        //penalty charged to staker
        uint256 penalty = stakes[_messageHash].bounty
        .mul(REVOCATION_PENALTY)
        .div(100);

        // burn staker penalty
        baseToken.transfer(address(0), penalty);

        // delete the stake data
        delete stakes[_messageHash];

        // Emit RevertedStake event
        emit RevertedStake(
            _messageHash,
            staker_,
            stakerNonce_,
            amount_
        );
    }

    /**
     * @notice Declare redemption intent
     *
     * @param _redeemer Redeemer address.
     * @param _redeemerNonce Redeemer nonce.
     * @param _beneficiary Address where the redeemed tokens will be
     *                     transferred.
     * @param _amount Redeem amount.
     * @param _gasPrice Gas price that redeemer is ready to pay to get the
     *                  redeem and unstake process done
     * @param _gasLimit Gas limit that redeemer is ready to pay.
     * @param _blockHeight Block number for which the proof is valid.
     * @param _hashLock Hash lock
     * @param _rlpEncodedParentNodes RLP encoded parent node data to prove
     *                               Declared in messageBox outbox
     *                               of CoGateway
     *
     * @return messageHash_ Message hash
     */
    function confirmRedemptionIntent(
        address _redeemer,
        uint256 _redeemerNonce,
        address _beneficiary,
        uint256 _amount,
        uint256 _gasPrice,
        uint256 _gasLimit,
        uint256 _blockHeight,
        bytes32 _hashLock,
        bytes memory _rlpEncodedParentNodes
    )
        public
        returns (bytes32 messageHash_)
    {
        // Get the initial gas
        uint256 initialGas = gasleft();

        require(
            _redeemer != address(0),
            "Redeemer address must not be zero"
        );
        require(
            _beneficiary != address(0),
            "Beneficiary address must not be zero"
        );
        require(
            _amount != 0,
            "Redeem amount must not be zero"
        );
        require(
            _gasPrice != 0,
            "Gas price must not be zero"
        );
        require(
            _gasLimit != 0,
            "Gas limit must not be zero"
        );
        require(
            _rlpEncodedParentNodes.length > 0,
            "RLP encoded parent nodes must not be zero"
        );

        // Get the redemption intent hash
        bytes32 intentHash = hashRedemptionIntent(
            _amount,
            _beneficiary,
            _redeemer,
            _redeemerNonce,
            _gasPrice,
            _gasLimit
        );

        // Get the message hash
        messageHash_ = MessageBus.messageDigest(
            REDEEM_TYPEHASH,
            intentHash,
            _redeemerNonce,
            _gasPrice,
            _gasLimit
        );

        registerInboxProcess(
            _redeemer,
            _redeemerNonce,
            messageHash_
        );

        unstakes[messageHash_] = Unstake({
            amount : _amount,
            beneficiary : _beneficiary
            });

        messages[messageHash_] = getMessage(
            _redeemer,
            _redeemerNonce,
            _gasPrice,
            _gasLimit,
            intentHash,
            _hashLock
        );

        executeConfirmRedemptionIntent(
            messages[messageHash_],
            _blockHeight,
            _rlpEncodedParentNodes
        );

        // Emit RedemptionIntentConfirmed event.
        emit RedemptionIntentConfirmed(
            messageHash_,
            _redeemer,
            _redeemerNonce,
            _beneficiary,
            _amount,
            _blockHeight,
            _hashLock
        );

        // Update the gas consumed for this function.
        messages[messageHash_].gasConsumed = initialGas.sub(gasleft());
    }

    /**
     * @notice Complete unstake
     *
     * @param _messageHash Message hash.
     * @param _unlockSecret Unlock secret for the hashLock provide by the
     *                      facilitator while initiating the redeem
     *
     * @return redeemer_ Redeemer address
     * @return beneficiary_ Address to which the tokens will be transferred.
     * @return redeemAmount_ Total amount for which the redemption was
     *                       initiated. The reward amount is deducted from the
     *                       total redemption amount and is given to the
     *                       facilitator.
     * @return unstakeAmount_ Actual unstake amount, after deducting the reward
     *                        from the total redeem amount.
     * @return rewardAmount_ Reward amount that is transferred to facilitator
     */
    function progressUnstake(
        bytes32 _messageHash,
        bytes32 _unlockSecret
    )
    external
    returns (
        uint256 redeemAmount_,
        uint256 unstakeAmount_,
        uint256 rewardAmount_
    )
    {
        // Get the inital gas
        uint256 initialGas = gasleft();

        require(
            _messageHash != bytes32(0),
            "Message hash must not be zero"
        );
        // Get the message object.
        MessageBus.Message storage message = messages[_messageHash];

        // Progress inbox
        MessageBus.progressInbox(
            messageBox,
            REDEEM_TYPEHASH,
            message,
            _unlockSecret
        );
        (redeemAmount_, unstakeAmount_, rewardAmount_) =
        progressUnstakeInternal(_messageHash, initialGas, _unlockSecret, false);

    }

    /**
     * @notice Completes the redemption process by providing the merkle proof
     *         instead of unlockSecret. In case the facilitator process is not
     *         able to complete the redeem and unstake process then this is an
     *         alternative approach to complete the process
     *
     * @dev This can be called to prove that the outbox status of messageBox on
     *      CoGateway is either declared or progressed.
     *
     * @param _messageHash Message hash.
     * @param _rlpEncodedParentNodes RLP encoded parent node data to prove in
     *                               messageBox inbox of CoGateway
     * @param _blockHeight Block number for which the proof is valid
     * @param _messageStatus Message status i.e. Declared or Progressed that
     *                       will be proved.
     *
     * @return redeemAmount_ Total amount for which the redemption was
     *                       initiated. The reward amount is deducted from the
     *                       total redemption amount and is given to the
     *                       facilitator.
     * @return unstakeAmount_ Actual unstake amount, after deducting the reward
     *                        from the total redeem amount.
     * @return rewardAmount_ Reward amount that is transferred to facilitator
     */
    function progressUnstakeWithProof(
        bytes32 _messageHash,
        bytes _rlpEncodedParentNodes,
        uint256 _blockHeight,
        uint256 _messageStatus
    )
    public
    returns (
        uint256 redeemAmount_,
        uint256 unstakeAmount_,
        uint256 rewardAmount_
    )
    {
        // Get the inital gas
        uint256 initialGas = gasleft();

        require(
            _messageHash != bytes32(0),
            "Message hash must not be zero"
        );
        require(
            _rlpEncodedParentNodes.length > 0,
            "RLP encoded parent nodes must not be zero"
        );

        // Get the storage root for the given block height
        bytes32 storageRoot = storageRoots[_blockHeight];
        require(
            storageRoot != bytes32(0),
            "Storage root must not be zero"
        );

        // Get the message object.
        MessageBus.Message storage message = messages[_messageHash];

        MessageBus.progressInboxWithProof(
            messageBox,
            REDEEM_TYPEHASH,
            message,
            _rlpEncodedParentNodes,
            MESSAGE_BOX_OFFSET,
            storageRoot,
            MessageBus.MessageStatus(_messageStatus)
        );

        (redeemAmount_, unstakeAmount_, rewardAmount_) =
        progressUnstakeInternal(_messageHash, initialGas, bytes32(0), true);
    }

    /**
     * @notice Declare redemption revert intent.
     *         This will set message status to revoked. This method will also
     *         clear unstakes mapping storage.
     *
     * @param _messageHash Message hash.
     * @param _blockHeight Block number for which the proof is valid
     * @param _rlpEncodedParentNodes RLP encoded parent node data to prove
     *                               DeclaredRevocation in messageBox outbox
     *                               of CoGateway
     *
     * @return redeemer_ Redeemer address
     * @return redeemerNonce_ Redeemer nonce
     * @return amount_ Redeem amount
     */
    function confirmRevertRedemptionIntent(
        bytes32 _messageHash,
        uint256 _blockHeight,
        bytes _rlpEncodedParentNodes
    )
    external
    returns (
        address redeemer_,
        uint256 redeemerNonce_,
        uint256 amount_
    )
    {
        // Get the initial gas value
        uint256 initialGas = gasleft();

        require(
            _messageHash != bytes32(0),
            "Message hash must not be zero"
        );
        require(
            _rlpEncodedParentNodes.length > 0,
            "RLP encoded parent nodes must not be zero"
        );

        // Get the message object.
        MessageBus.Message storage message = messages[_messageHash];
        require(
            message.intentHash != bytes32(0),
            "RevertRedemption intent hash must not be zero"
        );

        // Get the storage root
        bytes32 storageRoot = storageRoots[_blockHeight];
        require(
            storageRoot != bytes32(0),
            "Storage root must not be zero"
        );

        // Confirm revocation
        MessageBus.confirmRevocation(
            messageBox,
            REDEEM_TYPEHASH,
            message,
            _rlpEncodedParentNodes,
            MESSAGE_BOX_OFFSET,
            storageRoot
        );

        // delete the unstake data
        delete unstakes[_messageHash];

        redeemer_ = message.sender;
        redeemerNonce_ = message.nonce;
        amount_ = unstakes[_messageHash].amount;

        // Emit RevertRedemptionIntentConfirmed event
        emit RevertRedemptionIntentConfirmed(
            _messageHash,
            redeemer_,
            redeemerNonce_,
            amount_
        );

        // Update the gas consumed for this function.
        message.gasConsumed = initialGas.sub(gasleft());
    }

    /* private functions */

    /**
     * @notice private function to execute confirm redemption intent.
     *
     * @dev This function is to avoid stack too deep error in
     *      confirmRedemptionIntent function
     *
     * @param _message message object
     * @param _blockHeight Block number for which the proof is valid
     * @param _rlpParentNodes RLP encoded parent nodes.
     *
     * @return `true` if executed successfully
     */
    function executeConfirmRedemptionIntent(
        MessageBus.Message storage _message,
        uint256 _blockHeight,
        bytes _rlpParentNodes
    )
        private
        returns (bool)
    {
        // Get storage root
        bytes32 storageRoot = storageRoots[_blockHeight];
        require(
            storageRoot != bytes32(0),
            "Storage root must not be zero"
        );

        // Confirm message
        MessageBus.confirmMessage(
            messageBox,
            REDEEM_TYPEHASH,
            _message,
            _rlpParentNodes,
            MESSAGE_BOX_OFFSET,
            storageRoot
        );

        return true;
    }

    /**
     * @notice Internal function contains logic for process staking.
     *
     * @param _messageHash Message hash.
     * @param _unlockSecret For process with hash lock, proofProgress event
     *                      param is set to false otherwise set to true.
     *
     * @return staker_ Staker address
     * @return stakeAmount_ Stake amount
     * @return message_ Message Bus message
     */
    function progressStakingInternal(
        bytes32 _messageHash,
        bytes32 _unlockSecret,
        bool _proofProgress
    )
        private
        returns (
            address staker_,
            uint256 stakeAmount_,
            MessageBus.Message storage message_
        )
    {

        message_ = messages[_messageHash];
        // Get the staker address
        staker_ = message_.sender;

        //Get the stake amount
        stakeAmount_ = stakes[_messageHash].amount;

        // Transfer the staked amount to stakeVault.
        token.transfer(stakeVault, stakeAmount_);

        baseToken.transfer(msg.sender, stakes[_messageHash].bounty);

        // delete the stake data
        delete stakes[_messageHash];

        emit ProgressedStake(
            _messageHash,
            staker_,
            message_.nonce,
            stakeAmount_,
            _proofProgress,
            _unlockSecret
        );
    }
    /**
     * @notice This is internal method for process unstake called from external
     *         methods which processUnstake(with hashlock) and
     *         processUnstakeWithProof
     *
     * @param _messageHash hash to identify message
     * @param _initialGas initial available gas during process unstake call.
     * @param _unlockSecret Block number for which the proof is valid
     * @param _proofProgress true if progress with proof and false if
     *                       progress with unlock secret.
     *
     * @return redeemAmount_ Total amount for which the redemption was
     *                       initiated. The reward amount is deducted from the
     *                       total redemption amount and is given to the
     *                       facilitator.
     * @return unstakeAmount_ Actual unstake amount, after deducting the reward
     *                        from the total redeem amount.
     * @return rewardAmount_ Reward amount that is transferred to facilitator
     */
    function progressUnstakeInternal(
        bytes32 _messageHash,
        uint256 _initialGas,
        bytes32 _unlockSecret,
        bool _proofProgress
    )
        private
        returns (
            uint256 redeemAmount_,
            uint256 unstakeAmount_,
            uint256 rewardAmount_
        )
    {

        Unstake storage unStake = unstakes[_messageHash];
        // Get the message object.
        MessageBus.Message storage message = messages[_messageHash];

        redeemAmount_ = unStake.amount;

        //TODO: Remove the hardcoded 50000. Discuss and implement it properly
        //21000 * 2 for transactions + approx buffer

        (rewardAmount_, message.gasConsumed) = GatewayLib.feeAmount(
            message.gasConsumed,
            message.gasLimit,
            message.gasPrice,
            _initialGas,
            50000
        );

        unstakeAmount_ = redeemAmount_.sub(rewardAmount_);
        // Release the amount to beneficiary
        stakeVault.releaseTo(unStake.beneficiary, unstakeAmount_);

        //reward facilitator with the reward amount
        stakeVault.releaseTo(msg.sender, rewardAmount_);

        // delete the unstake data
        delete unstakes[_messageHash];

        emit ProgressedUnstake(
            _messageHash,
            message.sender,
            unStake.beneficiary,
            redeemAmount_,
            unstakeAmount_,
            redeemAmount_,
            _proofProgress,
            _unlockSecret
        );
    }

    /**
     * @notice private function to calculate redemption intent hash.
     *
     * @dev This function is to avoid stack too deep error in
     *      confirmRedemptionIntent function
     *
     * @param _amount redemption amount
     * @param _beneficiary unstake account
     * @param _redeemer redeemer account
     * @param _redeemer nonce of staker
     * @param _gasPrice price used for reward calculation
     * @param _gasLimit max limit for reward calculation
     *
     * @return bytes32 redemption intent hash
     */
    function hashRedemptionIntent(
        uint256 _amount,
        address _beneficiary,
        address _redeemer,
        uint256 _redeemerNonce,
        uint256 _gasPrice,
        uint256 _gasLimit
    )
        private
        view
        returns(bytes32)
    {
        return GatewayLib.hashRedemptionIntent(
            _amount,
            _beneficiary,
            _redeemer,
            _redeemerNonce,
            _gasPrice,
            _gasLimit,
            token
        );
    }

}



