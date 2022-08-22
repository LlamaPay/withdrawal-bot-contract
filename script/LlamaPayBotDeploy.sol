//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {LlamaPayBot} from "../src/LlamaPayBot.sol";

contract LlamaPayBotDeploy is Script {
    function run() public {
        vm.startBroadcast();
        LlamaPayBot llamaPayBot = new LlamaPayBot{salt: bytes32("llama")}(
            0xcCDd688d7eDcF89bFa217492E247d1395FcEC23D,
            0xA43bC77e5362a81b3AB7acCD8B7812a981bdA478,
            0xad730D8e730c99E205A371436cE2e5aCFC38D7F9
        );
    }
}
