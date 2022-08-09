//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

interface LlamaPay {
    function withdraw(
        address from,
        address to,
        uint216 amountPerSec
    ) external;
}

contract LlamaPayBot {
    using SafeTransferLib for ERC20;

    address public bot = 0xA43bC77e5362a81b3AB7acCD8B7812a981bdA478;
    address public llama = 0x7B3cCe19124aA3a4378768BF0EF6555709b51481;
    address public newLlama = 0x7B3cCe19124aA3a4378768BF0EF6555709b51481;
    uint256 public fee = 50000; // Covers bot gas cost for calling function

    event WithdrawScheduled(
        address llamaPay,
        address from,
        address to,
        uint216 amountPerSec,
        uint40 starts,
        uint40 frequency,
        bytes32 id
    );
    event RedirectScheduled(
        address from,
        address to,
        address token,
        uint256 amount,
        uint40 starts,
        uint40 frequency,
        bytes32 id
    );
    event WithdrawCancelled(
        address llamaPay,
        address from,
        address to,
        uint216 amountPerSec,
        uint40 starts,
        uint40 frequency,
        bytes32 id
    );
    event RedirectCancelled(
        address from,
        address to,
        address token,
        uint256 amount,
        uint40 starts,
        uint40 frequency,
        bytes32 id
    );
    event WithdrawExecuted(
        address llamaPay,
        address from,
        address to,
        uint216 amountPerSec,
        uint40 starts,
        uint40 frequency,
        bytes32 id
    );
    event RedirectExecuted(
        address from,
        address to,
        address token,
        uint256 amount,
        uint40 starts,
        uint40 frequency,
        bytes32 id
    );

    mapping(address => uint256) public balances;
    mapping(bytes32 => bool) public active;

    function deposit() external payable {
        require(msg.sender != bot, "bot cannot deposit");
        balances[msg.sender] += msg.value;
    }

    function refund() external {
        uint256 toSend = balances[msg.sender];
        balances[msg.sender] = 0;
        (bool sent, ) = msg.sender.call{value: toSend}("");
        require(sent, "failed to send ether");
    }

    function scheduleWithdraw(
        address _llamaPay,
        address _to,
        uint216 _amountPerSec,
        uint40 _starts,
        uint40 _frequency
    ) external {
        bytes32 id = calcWithdrawId(
            _llamaPay,
            msg.sender,
            _to,
            _amountPerSec,
            _starts,
            _frequency
        );
        require(!active[id], "already exists");
        active[id] = !active[id];
        emit WithdrawScheduled(
            _llamaPay,
            msg.sender,
            _to,
            _amountPerSec,
            _starts,
            _frequency,
            id
        );
    }

    function scheduleRedirect(
        address _to,
        address _token,
        uint256 _amount,
        uint40 _starts,
        uint40 _frequency
    ) external {
        bytes32 id = calcRedirectId(
            msg.sender,
            _to,
            _token,
            _amount,
            _starts,
            _frequency
        );
        require(!active[id], "already exists");
        active[id] = !active[id];
        emit RedirectScheduled(
            msg.sender,
            _to,
            _token,
            _amount,
            _starts,
            _frequency,
            id
        );
    }

    function cancelWithdraw(
        address _llamaPay,
        address _to,
        uint216 _amountPerSec,
        uint40 _starts,
        uint40 _frequency
    ) external {
        bytes32 id = calcWithdrawId(
            _llamaPay,
            msg.sender,
            _to,
            _amountPerSec,
            _starts,
            _frequency
        );
        require(active[id], "doesn't exist");
        active[id] = !active[id];
        emit WithdrawCancelled(
            _llamaPay,
            msg.sender,
            _to,
            _amountPerSec,
            _starts,
            _frequency,
            id
        );
    }

    function cancelRedirect(
        address _to,
        address _token,
        uint256 _amount,
        uint40 _starts,
        uint40 _frequency
    ) external {
        bytes32 id = calcRedirectId(
            msg.sender,
            _to,
            _token,
            _amount,
            _starts,
            _frequency
        );
        require(active[id], "doesn't exist");
        active[id] = !active[id];
        emit RedirectCancelled(
            msg.sender,
            _to,
            _token,
            _amount,
            _starts,
            _frequency,
            id
        );
    }

    function executeWithdraw(
        address _llamaPay,
        address _from,
        address _to,
        uint216 _amountPerSec,
        uint40 _starts,
        uint40 _frequency,
        bool _execute,
        bool _emitEvent
    ) external {
        require(msg.sender == bot, "not bot");
        bytes32 id = calcWithdrawId(
            _llamaPay,
            _from,
            _to,
            _amountPerSec,
            _starts,
            _frequency
        );
        require(active[id], "not active");
        if (_execute) {
            LlamaPay(_llamaPay).withdraw(_from, _to, _amountPerSec);
        }
        if (_emitEvent) {
            emit WithdrawExecuted(
                _llamaPay,
                _from,
                _to,
                _amountPerSec,
                _starts,
                _frequency,
                id
            );
        }
    }

    function executeRedirect(
        address _from,
        address _to,
        address _token,
        uint256 _amount,
        uint40 _starts,
        uint40 _frequency
    ) external {
        require(msg.sender == bot, "not bot");
        bytes32 id = calcRedirectId(
            _from,
            _to,
            _token,
            _amount,
            _starts,
            _frequency
        );
        require(active[id], "not active");
        ERC20(_token).safeTransferFrom(_from, _to, _amount);
        emit RedirectExecuted(
            _from,
            _to,
            _token,
            _amount,
            _starts,
            _frequency,
            id
        );
    }

    function execute(bytes[] calldata _calls, address _from) external {
        require(msg.sender == bot, "not bot");
        uint256 i;
        uint256 len = _calls.length;
        uint256 startGas = gasleft();
        for (i = 0; i < len; ++i) {
            address(this).delegatecall(_calls[i]);
        }
        uint256 gasUsed = ((startGas - gasleft()) + 21000) + fee;
        uint256 totalSpent = gasUsed * tx.gasprice;
        balances[_from] -= totalSpent;
        (bool sent, ) = bot.call{value: totalSpent}("");
        require(sent, "failed to send ether to bot");
    }

    function batchExecute(bytes[] calldata _calls) external {
        require(msg.sender == bot, "not bot");
        uint256 i;
        uint256 len = _calls.length;
        for (i = 0; i < len; ++i) {
            address(this).delegatecall(_calls[i]);
        }
    }

    function calcWithdrawId(
        address _llamaPay,
        address _from,
        address _to,
        uint216 _amountPerSec,
        uint40 _starts,
        uint40 _frequency
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _llamaPay,
                    _from,
                    _to,
                    _amountPerSec,
                    _starts,
                    _frequency
                )
            );
    }

    function calcRedirectId(
        address _from,
        address _to,
        address _token,
        uint256 _amount,
        uint40 _starts,
        uint40 _frequency
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _from,
                    _to,
                    _token,
                    _amount,
                    _starts,
                    _frequency
                )
            );
    }
}
