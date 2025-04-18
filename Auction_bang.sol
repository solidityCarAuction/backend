// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Auction {
    address internal auction_owner;
    uint256 public auction_start;
    uint256 public auction_end;
    uint256 public highestBid;
    address public highestBidder;
    // [NEW] isWithdraw = true 소유주가 출금 안한 상태 , false 출금한 상태
    bool internal  isWithdraw = true;
  
    enum auction_state {
        CANCELLED, STARTED
    }

    struct car {
        string Brand;
        string Rnumber;
    }

    car public Mycar;
    address[] bidders;
    mapping(address => uint) public bids;
    auction_state public STATE;
    
    // [NEW] 소유주가 경매를 중단했는지 확인하는 부분 추가
    // 경매가 진행 중인지 확인하는 modifier
    modifier an_ongoing_auction() {
        require(block.timestamp <= auction_end, "Auction has ended");
        require(STATE == auction_state.STARTED, "Auction was cancelled");
        _;
    }
    // [NEW]
    // 경매가 끝났는지 확인하는 modifier ( 시간이 끝났거나 경매 소유자가 경매를 중단했거나)
    modifier end_auction() {
        require(block.timestamp > auction_end || STATE == auction_state.CANCELLED, "Auction id ongoing");
        _;
    }
    // [NEW]
    // 경매소유자가 출금을 했는지 확인하는 modifier 
    modifier withdraw_owner() {
        require(isWithdraw, "You have already withdrawn");
        _;
    }

    // 경매 소유자만 호출할 수 있는 modifier
    modifier only_owner() {
        require(msg.sender == auction_owner, "Only auction owner can call this");
        _;
    }
    // [NEW]
    // 최고 금액 경매 참여자를 판단할수 있는 modifier
    modifier isHighestBidder() {
        require(msg.sender != highestBidder , "is the highest bidder");
        _;
    }

    // 함수 선언에 virtual 키워드 추가
    function bid() public payable virtual returns (bool) {}
    function withdraw() public virtual returns (bool) {}
    function cancel_auction() external virtual returns (bool) {}
    function withdrawRemainingFunds() external virtual {}

    // 이벤트 선언
    event BidEvent(address indexed highestBidder, uint256 highestBid);
    event WithdrawalEvent(address withdrawer, uint256 amount);
    event CanceledEvent(uint message, uint256 time);
    event StateUpdated(auction_state newState); // 상태 업데이트 이벤트 추가
    
}

contract MyAuction is Auction {

    // 생성자
    constructor(uint _biddingTime, address _owner, string memory _brand, string memory _Rnumber) {
        auction_owner = _owner;
        auction_start = block.timestamp;
        auction_end = auction_start + _biddingTime * 1 hours;
        STATE = auction_state.STARTED;
        Mycar.Brand = _brand;
        Mycar.Rnumber = _Rnumber;
    }
    // // [NEW]최고 입찰금액을 msg.value → bids[msg.sender] + msg.value로 수정해서 낮은금액으로 입찰하던것을 막음
    // 부모 컨트랙트의 bid 함수 재정의 (override)
    function bid() public payable override an_ongoing_auction returns (bool) {
        require (bids[msg.sender] + msg.value > highestBid, "Bid is too low");  
        highestBidder = msg.sender;
        highestBid = bids[msg.sender] + msg.value;
        bidders.push(msg.sender);
        bids[msg.sender] = bids[msg.sender] + msg.value;
        emit BidEvent(highestBidder, highestBid);
        return true;
        
    }

    // 부모 컨트랙트의 cancel_auction 함수 재정의 (override)
    function cancel_auction() external override only_owner an_ongoing_auction returns (bool) {
        STATE = auction_state.CANCELLED;
        emit CanceledEvent(1, block.timestamp);
        return true;
    }

    // 경매 비활성화 (selfdestruct 대신 사용)
    function deactivateAuction() external only_owner {
        require(block.timestamp > auction_end, "Auction is still ongoing");
        STATE = auction_state.CANCELLED;
        emit CanceledEvent(2, block.timestamp);
    }

    // [NEW] 경매 소유자는 경매가 끝난 이후에 스마트 컨트랙트 안의 금액중 최고 입찰자의 금액을 1회만 출금가능
    // 경매 소유자가 남은 자금을 회수하는 함수
    function withdrawRemainingFunds() external override only_owner end_auction withdraw_owner{
        uint amount = bids[highestBidder];
        isWithdraw = false;// [NEW]더는 출금 못하게 막음
        uint balance = address(this).balance;
        require(balance > 0, "No funds left in the contract");

        (bool success, ) = payable(auction_owner).call{value: amount}("");
        require(success, "Transfer failed");
    }



    // [NEW]isHighestBidder modifierf를 추가 해서 최고 입찰자는 출금불가
    // 출금 함수 (입찰자들이 자금을 출금)
    function withdraw() public override isHighestBidder returns (bool)  {
        uint amount = bids[msg.sender];
        require(amount > 0, "No funds to withdraw");

        bids[msg.sender] = 0;

        // 안전한 전송 방법 사용
        // (bool success, ) = payable(msg.sender).call{value: amount}("");
        (bool success, ) = payable(msg.sender).call{value: amount, gas: 5000}(""); 

        require(success, "Transfer failed");

        emit WithdrawalEvent(msg.sender, amount);
        return true;
    }

    // 소유자 정보 반환 함수
    function get_owner() public view returns (address) {
        return auction_owner;
    }

    // 경매 상태를 업데이트하는 함수
    function updateAuctionState(auction_state newState) external only_owner {
        STATE = newState;
        emit StateUpdated(newState); // 상태 업데이트 이벤트 발생
    }



}
