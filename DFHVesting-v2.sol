// contracts/DFHVesting-v2.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


contract DFHVestingToken is Ownable, Pausable {
    using SafeMath for uint256;

    uint256 public constant DECIMALS = 10 ** 18;
    uint256 private _start;
    uint256 private _end;
    uint256 private _cliff;
    uint256 private _startSecond;
    uint256 private _duration;
    uint256 private _firstReleasePercent;
    uint256 private _secondsPerSlice;
    uint256 private _periods;

    struct InfoVesting {
        uint256 amount;
        uint256 releasedAmount;
    }
    
    ERC20 private _token;
    mapping(address => InfoVesting) private listVesting;
        
    constructor(
        uint256 start,
        uint256 cliffDuration, // duration from start to first cliff
        uint256 cliffDuration2, // duration from first cliff to second cliff
        uint256 duration, // duration from start
        uint256 firstReleasePercent,
        uint256 secondsPerSlice
    ) {
        require(cliffDuration.add(cliffDuration2) <= duration, "DFHVesting: cliff is longer than duration");
        require(cliffDuration.add(cliffDuration2).add(secondsPerSlice) <= duration, "DFHVesting: seconds per slice is exceeded the end time");
        require(duration > 0, "DFHVesting: duration is 0");
        require(start.add(duration) > block.timestamp, "DFHVesting: ended before current time");

        _duration = duration;
        _start = start;
        _cliff = _start.add(cliffDuration);
        _startSecond = _start.add(cliffDuration).add(cliffDuration2);
        _end = _start.add(duration);
        _firstReleasePercent = firstReleasePercent;
        _secondsPerSlice = secondsPerSlice;
        _periods = duration.sub(cliffDuration).sub(cliffDuration2).div(secondsPerSlice);
    }

    function setToken (address token) public onlyOwner {
        require(token != address(0), "DFHVesting: DFH address is invalid");
        _token = ERC20(token);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
    
    function addVesting(
        address beneficiary,
        uint256 amount
    ) public onlyOwner {
        _addVesting(beneficiary, amount);
    }
    
    function addVestingBatch(
        address[] memory beneficiary,
        uint256 amount
    ) public onlyOwner {
        for (uint256 i=0; i < beneficiary.length; i++) {
            _addVesting(beneficiary[i], amount);
        }
    }

    function _addVesting(
        address beneficiary,
        uint256 amount
    ) internal {
        require(beneficiary != address(0), "DFHVesting: beneficiary is the zero address");
        InfoVesting memory info =
            InfoVesting(
                amount,
                0
            );
        listVesting[beneficiary] = info;
    }

    function release ()
        public
        whenNotPaused
    {
        uint256 currentTime = getCurrentTime();
        address beneficiary = _msgSender();
        uint256 claimableAmount = _estTokenReceived(beneficiary, currentTime);
        require(claimableAmount > 0, "DFHVesting: Insufficient balance");

        listVesting[beneficiary].releasedAmount = listVesting[beneficiary].releasedAmount.add(claimableAmount);

        _token.transfer(beneficiary, claimableAmount * DECIMALS);
        emit Received(beneficiary, claimableAmount);
    }

    function estTokenReceived (address beneficiary) public view returns (uint256) {
        uint256 currentTime = getCurrentTime();
        return _estTokenReceived(beneficiary, currentTime);
    }

    function estNextTokenReceived (address beneficiary) public view returns (uint256) {
        uint256 time = nextReleaseAt().add(1);
        if (time == 0) {
            time = getCurrentTime();
        }
        return _estTokenReceived(beneficiary, time);
    }

    function _estTokenReceived (address beneficiary, uint256 time) private view returns (uint256) {
        InfoVesting memory info = listVesting[beneficiary];
        return _vestableAmount(beneficiary, time).sub(info.releasedAmount);
    }

    function _vestableAmount(address beneficiary, uint256 time) 
        internal
        view
        returns (uint256)
    {
        InfoVesting memory info = listVesting[beneficiary];
        uint256 firstVestAmount = info.amount.mul(_firstReleasePercent).div(100);
        if (time > _startSecond) {
            uint256 durationFromStart = time.sub(_startSecond);
            uint256 vestedSlicePeriods = durationFromStart.div(_secondsPerSlice);
            if (vestedSlicePeriods.add(1) >= _periods) {
                return info.amount;
            }
            return (
                (info.amount.sub(firstVestAmount).mul(1000))
                    .div(_periods)
                    .mul(vestedSlicePeriods.add(1)) // Add 1 to release at the first month
                    .div(1000)
                ).add(firstVestAmount);
        } else if (time > _cliff) {
            return firstVestAmount;
        }
        return 0;
    }

    function _nextReleaseAt () internal view returns (uint256) {
        uint256 currentTime = getCurrentTime();
        if (currentTime > _end) {
            return 0;
        } else if (currentTime < _cliff) {
            return _cliff;
        } else if (currentTime < _startSecond) {
            return _startSecond;
        }
        uint256 durationFromStart = currentTime.sub(_startSecond);
        uint256 vestedSlicePeriods = durationFromStart.div(_secondsPerSlice);
        return _startSecond.add( vestedSlicePeriods.add(1).mul(_secondsPerSlice) );
    }

    function nextReleaseAt () public view returns (uint256) {
        return _nextReleaseAt();
    }

    function isWhitelisted(address beneficiary) public view returns(bool) {
        return listVesting[beneficiary].amount > 0;
    }

    function tokensRemain(address beneficiary) public view returns(uint256) {
        require(listVesting[beneficiary].amount > 0, "DFHVesting: User is not whitelisted");
        return listVesting[beneficiary].amount - listVesting[beneficiary].releasedAmount;
    }

    function getLocked(address beneficiary) external view returns (InfoVesting memory) {
        InfoVesting memory info = listVesting[beneficiary];
        return info;
    }

    function getBalanceToken() public view returns( uint256 ) {
        return IERC20(_token).balanceOf(address(this));
    }

    function withdrawToken(IERC20 token, uint256 _amount) public onlyOwner {
        require(_amount > 0 , "DFHVesting: _amount must be greater than 0");
        require(token.balanceOf(address(this)) >= _amount , "DFHVesting: Balance Of Token is not enough");
        token.transfer(msg.sender, _amount);
    }

    function withdrawTokenAll(IERC20 token) public onlyOwner {
        require(token.balanceOf(address(this)) > 0 , "DFHVesting: Balance Of Token is equal 0");
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    event Received(address, uint);

    function getCurrentTime()
        internal
        virtual
        view
        returns(uint256){
        return block.timestamp;
    }
}
