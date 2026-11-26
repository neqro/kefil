// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Minimal view of the SPACE ID Agent ID contract on BNB Chain
///         (0x60b9262456de011f7d15a54cdd8c48baaa8b022f, ERC-721, non-transferable).
interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title Kefil — an on-chain trust network for Agent ID holders
/// @notice Agent ID holders vouch for ("kefil olmak") or flag each other.
///         Vouching is reputation at stake: if an agent you vouched for gets
///         flagged by enough holders, your own score drops too.
///         Any dApp can read `trustScore` / `isTrusted` to gate access.
/// @dev    No owner, no admin, no upgradeability, no funds held, no token.
///         Nothing in this contract can move user assets.
contract Kefil {
    IAgentID public immutable agentId;

    uint256 public constant MAX_VOUCHES_OUT = 20;   // limits sybil "vouch spam"
    uint256 public constant FLAG_THRESHOLD = 5;     // flags needed to mark an agent risky
    int256 public constant VOUCH_POINTS = 10;       // per vouch received
    int256 public constant FLAG_POINTS = 10;        // per flag received
    int256 public constant BAD_VOUCH_PENALTY = 15;  // per vouched agent that became risky

    // vouches
    mapping(address => address[]) private _vouchOut;  // voucher => targets
    mapping(address => address[]) private _vouchIn;   // target  => vouchers
    mapping(address => mapping(address => uint256)) private _outIdx; // 1-based
    mapping(address => mapping(address => uint256)) private _inIdx;  // 1-based

    // flags
    mapping(address => mapping(address => bool)) public hasFlagged; // flagger => target
    mapping(address => uint256) public flagCount;

    event Vouched(address indexed voucher, address indexed target, string note);
    event VouchRevoked(address indexed voucher, address indexed target);
    event Flagged(address indexed flagger, address indexed target, string reason);
    event FlagRevoked(address indexed flagger, address indexed target);

    error NoAgentId(address account);
    error SelfAction();
    error AlreadyDone();
    error NotFound();
    error TooManyVouches();
    error NoteTooLong();

    constructor(address agentIdContract) {
        agentId = IAgentID(agentIdContract);
    }

    modifier bothAgents(address target) {
        if (target == msg.sender) revert SelfAction();
        if (agentId.balanceOf(msg.sender) == 0) revert NoAgentId(msg.sender);
        if (agentId.balanceOf(target) == 0) revert NoAgentId(target);
        _;
    }

    // ───────────── vouching ─────────────

    function vouch(address target, string calldata note) external bothAgents(target) {
        if (bytes(note).length > 140) revert NoteTooLong();
        if (_outIdx[msg.sender][target] != 0) revert AlreadyDone();
        if (_vouchOut[msg.sender].length >= MAX_VOUCHES_OUT) revert TooManyVouches();

        _vouchOut[msg.sender].push(target);
        _outIdx[msg.sender][target] = _vouchOut[msg.sender].length;
        _vouchIn[target].push(msg.sender);
        _inIdx[target][msg.sender] = _vouchIn[target].length;

        emit Vouched(msg.sender, target, note);
    }

    function revokeVouch(address target) external {
        uint256 o = _outIdx[msg.sender][target];
        if (o == 0) revert NotFound();
        _removeAt(_vouchOut[msg.sender], _outIdx[msg.sender], o, target);
        _removeAt(_vouchIn[target], _inIdx[target], _inIdx[target][msg.sender], msg.sender);
        emit VouchRevoked(msg.sender, target);
    }

    // ───────────── flagging ─────────────

    function flag(address target, string calldata reason) external bothAgents(target) {
        if (bytes(reason).length > 140) revert NoteTooLong();
        if (hasFlagged[msg.sender][target]) revert AlreadyDone();
        hasFlagged[msg.sender][target] = true;
        flagCount[target] += 1;
        emit Flagged(msg.sender, target, reason);
    }

    function revokeFlag(address target) external {
        if (!hasFlagged[msg.sender][target]) revert NotFound();
        hasFlagged[msg.sender][target] = false;
        flagCount[target] -= 1;
        emit FlagRevoked(msg.sender, target);
    }

    // ───────────── reads (free, for any dApp) ─────────────

    function isRisky(address a) public view returns (bool) {
        return flagCount[a] >= FLAG_THRESHOLD;
    }

    /// @notice Vouches that still count: the voucher must still hold an Agent ID
    ///         and must not itself be risky.
    function validVouchesIn(address a) public view returns (uint256 n) {
        address[] storage v = _vouchIn[a];
        for (uint256 i; i < v.length; ++i) {
            if (agentId.balanceOf(v[i]) > 0 && !isRisky(v[i])) ++n;
        }
    }

    /// @notice Agents this address vouched for that have since become risky.
    function badVouches(address a) public view returns (uint256 n) {
        address[] storage t = _vouchOut[a];
        for (uint256 i; i < t.length; ++i) if (isRisky(t[i])) ++n;
    }

    /// @notice score = 10 × valid vouches − 10 × flags − 15 × bad vouches.
    ///         Returns 0 for addresses without an Agent ID.
    function trustScore(address a) public view returns (int256) {
        if (agentId.balanceOf(a) == 0) return 0;
        return int256(validVouchesIn(a)) * VOUCH_POINTS
            - int256(flagCount[a]) * FLAG_POINTS
            - int256(badVouches(a)) * BAD_VOUCH_PENALTY;
    }

    /// @notice One-line gate for other dApps: `require(kefil.isTrusted(user, 30))`.
    function isTrusted(address a, int256 minScore) external view returns (bool) {
        return !isRisky(a) && trustScore(a) >= minScore;
    }

    function vouchersOf(address a) external view returns (address[] memory) { return _vouchIn[a]; }
    function vouchedBy(address a) external view returns (address[] memory) { return _vouchOut[a]; }
    function hasVouched(address voucher, address target) external view returns (bool) {
        return _outIdx[voucher][target] != 0;
    }

    function profile(address a) external view returns (
        bool holdsAgentId, int256 score, uint256 vouchesIn, uint256 vouchesOut,
        uint256 flags, uint256 bad, bool risky
    ) {
        return (agentId.balanceOf(a) > 0, trustScore(a), validVouchesIn(a),
                _vouchOut[a].length, flagCount[a], badVouches(a), isRisky(a));
    }

    // ───────────── internal ─────────────

    function _removeAt(
        address[] storage arr,
        mapping(address => uint256) storage idx,
        uint256 oneBased,
        address item
    ) private {
        uint256 last = arr.length;
        if (oneBased != last) {
            address moved = arr[last - 1];
            arr[oneBased - 1] = moved;
            idx[moved] = oneBased;
        }
        arr.pop();
        delete idx[item];
    }
}
