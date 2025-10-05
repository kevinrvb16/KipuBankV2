// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title AggregatorV3Interface
 * @notice Interface for Chainlink Data Feeds
 * @dev This interface allows contracts to interact with Chainlink Price Feeds
 */
interface AggregatorV3Interface {
    /**
     * @notice Returns the number of decimals present in the response value
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns a description of the price feed
     */
    function description() external view returns (string memory);

    /**
     * @notice Returns the version of the aggregator
     */
    function version() external view returns (uint256);

    /**
     * @notice Returns data about a specific round
     * @param _roundId The round ID to retrieve the data for
     * @return roundId The round ID
     * @return answer The price
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /**
     * @notice Returns the latest round data
     * @return roundId The round ID
     * @return answer The price
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
