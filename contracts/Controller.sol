// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../interfaces/IRelayEncoder.sol";
import "../interfaces/IxTokens.sol";
import "../interfaces/IXcmTransactor.sol";
import "../interfaces/ILedger.sol";
import "../interfaces/IAuthManager.sol";
import "../interfaces/ILido.sol";



contract Controller is Initializable {
    // Event emitted when weight updated
    event WeightUpdated (
        uint8 index,
        uint64 newValue
    );

    // Event emitted when bond called on relay chain
    event Bond (
        address caller,
        bytes32 stash,
        bytes32 controller,
        uint256 amount
    );

    // Event emitted when bond extra called on relay chain
    event BondExtra (
        address caller,
        bytes32 stash,
        uint256 amount
    );

    // Event emitted when unbond on relay chain
    event Unbond (
        address caller,
        bytes32 stash,
        uint256 amount
    );

    // Event emitted when rebond called on relay chain
    event Rebond (
        address caller,
        bytes32 stash,
        uint256 amount
    );

    // Event emitted when withdraw called on relay chain
    event Withdraw (
        address caller,
        bytes32 stash
    );

    // Event emitted when nominate called on relay chain
    event Nominate (
        address caller,
        bytes32 stash,
        bytes32[] validators
    );

    // Event emitted when chill called on relay chain
    event Chill (
        address caller,
        bytes32 stash
    );

    // Event emitted when transfer vKSM from parachain to relay chain called
    event TransferToRelaychain (
        address from,
        bytes32 to,
        uint256 amount
    );

    // Event emitted when transfer KSM from relay chain to parachain called
    event TransferToParachain (
        bytes32 from,
        address to,
        uint256 amount
    );

    // ledger controller account
    uint16 public rootDerivativeIndex;

    // vKSM precompile
    IERC20 internal VKSM;

    // relay call builder precompile
    IRelayEncoder internal RELAY_ENCODER;

    // xcm transactor precompile
    IXcmTransactor internal XCM_TRANSACTOR;

    // xTokens precompile
    IxTokens internal X_TOKENS;

    // LIDO address
    address public LIDO;

    // first hex for encodeTransfer
    bytes public hex1;

    // second hex for encodeTransfer
    bytes public hex2;

    // Second layer derivative-proxy account to index
    mapping(address => uint16) public senderToIndex;

    // Index to second layer derivative-proxy account
    mapping(uint16 => bytes32) public indexToAccount;

    // Enumerator for weights
    enum WEIGHT {
        AS_DERIVATIVE,              // 410_000_000
        BOND_BASE,                  // 600_000_000
        BOND_EXTRA_BASE,            // 1_100_000_000
        UNBOND_BASE,                // 1_250_000_000
        WITHDRAW_UNBONDED_BASE,     // 500_000_000
        WITHDRAW_UNBONDED_PER_UNIT, // 60_000
        REBOND_BASE,                // 1_200_000_000
        REBOND_PER_UNIT,            // 40_000
        CHILL_BASE,                 // 900_000_000
        NOMINATE_BASE,              // 1_000_000_000
        NOMINATE_PER_UNIT,          // 31_000_000
        TRANSFER_TO_PARA_BASE,      // 700_000_000
        TRANSFER_TO_RELAY_BASE      // 4_000_000_000
    }

    // Constant for max weight
    uint64 public MAX_WEIGHT;// = 1_835_300_000;

    // Array with current weights
    uint64[] public weights;

    // Parachain side fee on reverse transfer
    uint256 public REVERSE_TRANSFER_FEE;// = 4_000_000

    // Controller manager role
    bytes32 internal constant ROLE_CONTROLLER_MANAGER = keccak256("ROLE_CONTROLLER_MANAGER");

    // Allows function calls only for registered ledgers
    modifier onlyRegistred() {
        require(senderToIndex[msg.sender] != 0, "CONTROLLER: UNREGISTERED_SENDER");
        _;
    }

    // Allows function calls only for members with role
    modifier auth(bytes32 role) {
        require(IAuthManager(ILido(LIDO).AUTH_MANAGER()).has(role, msg.sender), "CONTROLLER: UNAUTHOROZED");
        _;
    }

    // Allows function calls only for LIDO contract
    modifier onlyLido() {
        require(msg.sender == LIDO, "CONTROLLER: CALLER_NOT_LIDO");
        _;
    }

    /**
    * @notice Initialize ledger contract.
    * @param _rootDerivativeIndex - stash account id
    * @param _vKSM - vKSM contract address
    * @param _relayEncoder - relayEncoder(relaychain calls builder) contract address
    * @param _xcmTransactor - xcmTransactor(relaychain calls relayer) contract address
    * @param _xTokens - minimal allowed nominator balance
    * @param _hex1 - first hex for encodeTransfer
    * @param _hex2 - second hex for encodeTransfer
    */
    function initialize(
        uint16 _rootDerivativeIndex,
        address _vKSM,
        address _relayEncoder,
        address _xcmTransactor,
        address _xTokens,
        bytes calldata _hex1,
        bytes calldata _hex2
    ) external initializer {
        require(address(VKSM) == address(0), "CONTROLLER: ALREADY_INITIALIZED");

        rootDerivativeIndex = _rootDerivativeIndex;

        VKSM = IERC20(_vKSM);
        RELAY_ENCODER = IRelayEncoder(_relayEncoder);
        XCM_TRANSACTOR = IXcmTransactor(_xcmTransactor);
        X_TOKENS = IxTokens(_xTokens);

        hex1 = _hex1;
        hex2 = _hex2;
    }

    /**
    * @notice Get current weight by enum
    * @param weightType - enum index of weight
    */
    function getWeight(WEIGHT weightType) public view returns(uint64) {
        return weights[uint256(weightType)];
    }

    /**
    * @notice Set new max weight. Can be called only by ROLE_CONTROLLER_MANAGER
    * @param _maxWeight - max weight
    */
    function setMaxWeight(uint64 _maxWeight) external auth(ROLE_CONTROLLER_MANAGER) {
        MAX_WEIGHT = _maxWeight;
    }

    /**
    * @notice Set new REVERSE_TRANSFER_FEE
    * @param _reverseTransferFee - new fee
    */
    function setReverseTransferFee(uint256 _reverseTransferFee) external auth(ROLE_CONTROLLER_MANAGER) {
        REVERSE_TRANSFER_FEE = _reverseTransferFee;
    }

    /**
    * @notice Set new hexes parametes for encodeTransfer
    * @param _hex1 - first hex for encodeTransfer
    * @param _hex2 - second hex for encodeTransfer
    */
    function updateHexParameters(bytes calldata _hex1, bytes calldata _hex2) external auth(ROLE_CONTROLLER_MANAGER) {
        hex1 = _hex1;
        hex2 = _hex2;
    }

    /**
    * @notice Set LIDO address. Function can be called only once
    * @param _lido - LIDO address
    */
    function setLido(address _lido) external {
        require(LIDO == address(0) && _lido != address(0), "CONTROLLER: LIDO_ALREADY_INITIALIZED");
        LIDO = _lido;
    }

    /**
    * @notice Update weights array. Weight updated only if weight = _weight | 1 << 65
    * @param _weights - weights array
    */
    function setWeights(
        uint128[] calldata _weights
    ) external auth(ROLE_CONTROLLER_MANAGER) {
        require(_weights.length == uint256(type(WEIGHT).max) + 1, "CONTROLLER: WRONG_WEIGHTS_SIZE");
        for (uint256 i = 0; i < _weights.length; ++i) {
            if ((_weights[i] >> 64) > 0) { // if _weights[i] = _weights[i] | 1 << 65 we must update i-th weight
                if (weights.length == i) {
                    weights.push(0);
                }

                weights[i] = uint64(_weights[i]);
                emit WeightUpdated(uint8(i), weights[i]);
            }
        }
    }

    /**
    * @notice Register new ledger contract
    * @param index - index of ledger contract
    * @param accountId - relay chain address of ledger
    * @param paraAddress - parachain address of ledger
    */
    function newSubAccount(uint16 index, bytes32 accountId, address paraAddress) external onlyLido {
        require(indexToAccount[index + 1] == bytes32(0), "CONTROLLER: ALREADY_REGISTERED");

        senderToIndex[paraAddress] = index + 1;
        indexToAccount[index + 1] = accountId;
    }

    /**
    * @notice Nominate validators from ledger on relay chain
    * @param validators - validators addresses to nominate
    */
    function nominate(bytes32[] calldata validators) external onlyRegistred {
        uint256[] memory convertedValidators = new uint256[](validators.length);
        for (uint256 i = 0; i < validators.length; ++i) {
            convertedValidators[i] = uint256(validators[i]);
        }
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.NOMINATE_BASE) + getWeight(WEIGHT.NOMINATE_PER_UNIT) * uint64(validators.length),
            RELAY_ENCODER.encode_nominate(convertedValidators)
        );

        emit Nominate(msg.sender, getSenderAccount(), validators);
    }

    /**
    * @notice Bond KSM of ledger on relay chain
    * @param controller - controller which used to bond
    * @param amount - amount of KSM to bond
    */
    function bond(bytes32 controller, uint256 amount) external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.BOND_BASE),
            RELAY_ENCODER.encode_bond(uint256(controller), amount, bytes(hex"00"))
        );

        emit Bond(msg.sender, getSenderAccount(), controller, amount);
    }

    /**
    * @notice Bond extra KSM of ledger on relay chain
    * @param amount - extra amount of KSM to bond
    */
    function bondExtra(uint256 amount) external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.BOND_EXTRA_BASE),
            RELAY_ENCODER.encode_bond_extra(amount)
        );

        emit BondExtra(msg.sender, getSenderAccount(), amount);
    }

    /**
    * @notice Unbond KSM of ledger on relay chain
    * @param amount - amount of KSM to unbond
    */
    function unbond(uint256 amount) external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.UNBOND_BASE),
            RELAY_ENCODER.encode_unbond(amount)
        );

        emit Unbond(msg.sender, getSenderAccount(), amount);
    }

    /**
    * @notice Withdraw unbonded tokens (move unbonded tokens to free)
    * @param slashingSpans - number of slashes received by ledger in case if we trying set ledger bonded balance < min, 
    in other cases = 0
    */
    function withdrawUnbonded(uint32 slashingSpans) external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.WITHDRAW_UNBONDED_BASE) + getWeight(WEIGHT.WITHDRAW_UNBONDED_PER_UNIT) * slashingSpans,
            RELAY_ENCODER.encode_withdraw_unbonded(slashingSpans)
        );

        emit Withdraw(msg.sender, getSenderAccount());
    }

    /**
    * @notice Rebond KSM of ledger from unbonded chunks on relay chain
    * @param amount - amount of KSM to rebond
    * @param unbondingChunks - amount of unbonding chunks to rebond
    */
    function rebond(uint256 amount, uint256 unbondingChunks) external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.REBOND_BASE) + getWeight(WEIGHT.REBOND_PER_UNIT) * uint64(unbondingChunks),
            RELAY_ENCODER.encode_rebond(amount)
        );

        emit Rebond(msg.sender, getSenderAccount(), amount);
    }

    /**
    * @notice Put ledger to chill mode
    */
    function chill() external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.CHILL_BASE),
            RELAY_ENCODER.encode_chill()
        );

        emit Chill(msg.sender, getSenderAccount());
    }

    /**
    * @notice Transfer KSM from relay chain to parachain
    * @param amount - amount of KSM to transfer
    */
    function transferToParachain(uint256 amount) external onlyRegistred {
        // to - msg.sender, from - getSenderIndex()
        uint256 parachain_fee = REVERSE_TRANSFER_FEE;

        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.TRANSFER_TO_PARA_BASE),
            encodeReverseTransfer(msg.sender, amount)
        );

        // compensate parachain side fee on reverse transfer
        if (amount <= parachain_fee) {
            // if amount less than fee just transfer amount
            VKSM.transfer(msg.sender, amount);
        }
        else {
            // else just compensate fee
            VKSM.transfer(msg.sender, parachain_fee);
        }

        emit TransferToParachain(getSenderAccount(), msg.sender, amount);
    }

    /**
    * @notice Transfer vKSM from parachain to relay chain
    * @param amount - amount of vKSM to transfer
    */
    function transferToRelaychain(uint256 amount) external onlyRegistred {
        // to - getSenderIndex(), from - msg.sender
        VKSM.transferFrom(msg.sender, address(this), amount);
        IxTokens.Multilocation memory destination;
        destination.parents = 1;
        destination.interior = new bytes[](1);
        destination.interior[0] = bytes.concat(bytes1(hex"01"), getSenderAccount(), bytes1(hex"00")); // X2, NetworkId: Any
        X_TOKENS.transfer(address(VKSM), amount + 18900000000, destination, getWeight(WEIGHT.TRANSFER_TO_RELAY_BASE));

        emit TransferToRelaychain(msg.sender, getSenderAccount(), amount);
    }

    /**
    * @notice Get index of registered ledger
    */
    function getSenderIndex() internal returns(uint16) {
        return senderToIndex[msg.sender] - 1;
    }

    /**
    * @notice Get relay chain address of msg.sender
    */
    function getSenderAccount() internal returns(bytes32) {
        return indexToAccount[senderToIndex[msg.sender]];
    }

    /**
    * @notice Send call to relay cahin through xcm transactor
    * @param index - index of ledger on relay chain
    * @param weight - fees on tx execution
    * @param call - bytes for tx execution
    */
    function callThroughDerivative(uint16 index, uint64 weight, bytes memory call) internal {
        bytes memory le_index = new bytes(2);
        le_index[0] = bytes1(uint8(index));
        le_index[1] = bytes1(uint8(index >> 8));

        uint64 total_weight = weight + getWeight(WEIGHT.AS_DERIVATIVE);
        require(total_weight <= MAX_WEIGHT, "CONTROLLER: TOO_MUCH_WEIGHT");

        XCM_TRANSACTOR.transact_through_derivative(
            0, // The transactor to be used
            rootDerivativeIndex, // The index to be used
            address(VKSM), // Address of the currencyId of the asset to be used for fees
            total_weight, // The weight we want to buy in the destination chain
            bytes.concat(hex"1001", le_index, call) // The inner call to be executed in the destination chain
        );
    }

    /**
    * @notice Encoding bytes to call transfer on relay chain
    * @param to - address of KSM receiver
    * @param amount - amount of KSM to send
    */
    function encodeReverseTransfer(address to, uint256 amount) internal returns(bytes memory) {
        return bytes.concat(
            hex1,
            abi.encodePacked(to),
            hex2,
            scaleCompactUint(amount),
            hex"00000000"
        );
    }

    /**
    * @notice Converting uint256 value to le bytes
    * @param value - uint256 value
    * @param len - length of output bytes array
    */
    function toLeBytes(uint256 value, uint256 len) internal returns(bytes memory) {
        bytes memory out = new bytes(len);
        for (uint256 idx = 0; idx < len; ++idx) {
            out[idx] = bytes1(uint8(value));
            value = value >> 8;
        }
        return out;
    }

    /**
    * @notice Converting uint256 value to bytes
    * @param value - uint256 value
    */
    function scaleCompactUint(uint256 value) internal returns(bytes memory) {
        if (value < 1<<6) {
            return toLeBytes(value << 2, 1);
        }
        else if(value < 1 << 14) {
            return toLeBytes((value << 2) + 1, 2);
        }
        else if(value < 1 << 30) {
            return toLeBytes((value << 2) + 2, 4);
        }
        else {
            uint256 numBytes = 0;
            {
                uint256 m = value;
                for (; numBytes < 256 && m != 0; ++numBytes) {
                    m = m >> 8;
                }
            }

            bytes memory out = new bytes(numBytes + 1);
            out[0] = bytes1(uint8(((numBytes - 4) << 2) + 3));
            for (uint256 i = 0; i < numBytes; ++i) {
                out[i + 1] = bytes1(uint8(value & 0xFF));
                value = value >> 8;
            }
            return out;
        }
    }
}
