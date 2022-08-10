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

    function withdrawable(
        address from,
        address to,
        uint216 amountPerSec
    )
        external
        view
        returns (
            uint256 withdrawableAmount,
            uint256 lastUpdate,
            uint256 owed
        );
}

contract LlamaPayBot {
    using SafeTransferLib for ERC20;
    address public bot = 0xA43bC77e5362a81b3AB7acCD8B7812a981bdA478;
    address public llama = 0x7B3cCe19124aA3a4378768BF0EF6555709b51481;
    address public newLlama = 0x7B3cCe19124aA3a4378768BF0EF6555709b51481;
    uint256 public fee = 50000; // Covers bot gas cost for calling function

    event WithdrawScheduled(
        address owner,
        address llamaPay,
        address from,
        address to,
        address token,
        address redirectTo,
        uint216 amountPerSec,
        uint40 starts,
        uint40 frequency,
        bytes32 id
    );

    event WithdrawCancelled(
        address owner,
        address llamaPay,
        address from,
        address to,
        address token,
        address redirectTo,
        uint216 amountPerSec,
        uint40 starts,
        uint40 frequency,
        bytes32 id
    );

    event WithdrawExecuted(
        address owner,
        address llamaPay,
        address from,
        address to,
        address token,
        address redirectTo,
        uint216 amountPerSec,
        uint40 starts,
        uint40 frequency,
        bytes32 id
    );

    mapping(address => uint256) public balances;
    mapping(bytes32 => address) public owners;

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
        address _from,
        address _to,
        address _token,
        address _redirectTo,
        uint216 _amountPerSec,
        uint40 _starts,
        uint40 _frequency
    ) external {
        bytes32 id = calcWithdrawId(
            _llamaPay,
            _from,
            _to,
            _token,
            _redirectTo,
            _amountPerSec,
            _starts,
            _frequency
        );
        require(owners[id] == address(0), "already exists");
        owners[id] = msg.sender;
        emit WithdrawScheduled(
            msg.sender,
            _llamaPay,
            _from,
            _to,
            _token,
            _redirectTo,
            _amountPerSec,
            _starts,
            _frequency,
            id
        );
    }

    function cancelWithdraw(
        address _llamaPay,
        address _from,
        address _to,
        address _token,
        address _redirectTo,
        uint216 _amountPerSec,
        uint40 _starts,
        uint40 _frequency
    ) external {
        bytes32 id = calcWithdrawId(
            _llamaPay,
            _from,
            _to,
            _token,
            _redirectTo,
            _amountPerSec,
            _starts,
            _frequency
        );
        require(owners[id] == msg.sender, "not owner");
        owners[id] = address(0);
        emit WithdrawCancelled(
            msg.sender,
            _llamaPay,
            _from,
            _to,
            _token,
            _redirectTo,
            _amountPerSec,
            _starts,
            _frequency,
            id
        );
    }

    function executeWithdraw(
        address _owner,
        address _llamaPay,
        address _from,
        address _to,
        address _token,
        address _redirectTo,
        uint216 _amountPerSec,
        uint40 _starts,
        uint40 _frequency,
        bytes32 _id,
        bool _execute,
        bool _emitEvent
    ) external {
        require(msg.sender == bot, "not bot");
        if (_execute) {
            if (_redirectTo != address(0)) {
                (uint256 withdrawableAmount, , ) = LlamaPay(_llamaPay)
                    .withdrawable(_from, _to, _amountPerSec);
                LlamaPay(_llamaPay).withdraw(_from, _to, _amountPerSec);
                ERC20(_token).safeTransferFrom(
                    _to,
                    _redirectTo,
                    withdrawableAmount
                );
            } else {
                LlamaPay(_llamaPay).withdraw(_from, _to, _amountPerSec);
            }
        }
        if (_emitEvent) {
            emit WithdrawExecuted(
                _owner,
                _llamaPay,
                _from,
                _to,
                _token,
                _redirectTo,
                _amountPerSec,
                _starts,
                _frequency,
                _id
            );
        }
    }

    function calcWithdrawId(
        address _llamaPay,
        address _from,
        address _to,
        address _token,
        address _redirectTo,
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
                    _token,
                    _redirectTo,
                    _amountPerSec,
                    _starts,
                    _frequency
                )
            );
    }
}
