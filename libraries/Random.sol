// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

/* "random" numbers generator
   rand(uint256 seed) - returns random number generated by seed
   randint() - returns random number with current time as seed
   randbytes(uint256 size) - returns byte array of random bytes
*/

/// @title Library Random
/// @custom:security-contact general@palmeradao.xyz
library Random {
    /**
     * @dev Generate random uint256 <= 256^2
     * @param _seed number seed to generate random number
     * @return uint
     */
    function rand(uint256 _seed) public view returns (uint256) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp +
                        block.prevrandao +
                        ((
                            uint256(keccak256(abi.encodePacked(block.coinbase)))
                        ) / (_seed)) +
                        block.gaslimit +
                        ((uint256(keccak256(abi.encodePacked(msg.sender)))) /
                            (_seed)) +
                        block.number
                )
            )
        );

        return (seed - ((seed * 1e18) / 1e18));
    }

    /**
     * @dev Generate random uint256 <= 256^2 with seed = block.timestamp
     * @return uint
     */
    function randint() internal view returns (uint256) {
        return rand(block.timestamp);
    }

    /**
     * @dev Generate random uint256 in range [a, b]
     * @return uint
     */
    function randrange(uint256 a, uint256 b) internal view returns (uint256) {
        return a + (randint() % b);
    }
}
