# 스마트 컨트랙트 개선 사항

## 개요
본 프로젝트는 이더리움 블록체인 상에서 동작하는 간단한 경매 스마트 컨트랙트입니다. 지정된 기간 동안 사용자들이 입찰에 참여할 수 있으며, 경매 종료 후 최고 입찰자가 결정되고 입찰에 참여한 사용자들이 자신의 금액을 관리할 수 있도록 설계되었습니다.

기반 코드
본 스마트 컨트랙트는 폴리텍 대학 서울 강서 캠퍼스 스마트 금융과 황원용 교수님께서 제공하신 13_auction.sol 파일을 기반으로, 기능 개선 및 잠재적 문제 해결을 위해 다음과 같은 수정 사항을 Auction_bang.sol 에 적용했습니다.
이 문서는  Auction_bang.sol 에 적용된 개선 사항들을 설명합니다. 이러한 변경의 목적은 경매 프로세스의 견고성, 보안성 및 사용자 경험을 향상시키는 것입니다. 주요 수정 사항은 입찰 검증 강화, 경매 소유자 및 입찰자의 인출 제어, 그리고 경매 상태 관리 개선에 중점을 둡니다.

## 계약 구조

![솔리디티클래스다이어그램 drawio](https://github.com/user-attachments/assets/5a38d9a3-0e08-4578-887b-02504c8afd26)

* **`Auction`**: 일반적인 경매를 위한 핵심 구조, 상태 변수, 변경자(modifier), 이벤트 및 가상 함수(virtual functions)를 정의하는 추상 기반 계약입니다.
* **`MyAuction`**: `Auction` 계약을 상속받는 구체적인 구현 계약입니다. 생성자 초기화 및 `bid`, `withdraw`, `cancel_auction`과 같은 가상 함수의 재정의(override)를 포함한 특정 경매 로직을 제공합니다.

## 새로운 기능 및 개선 사항 ([NEW])

새롭게 추가되거나 변경된 기능 및 로직은 다음과 같습니다.

1.  **소유자 인출 상태 추적 (`isWithdraw` 변수)**

    * **코드:** `bool internal isWithdraw = true;`
    * **설명:** `isWithdraw`라는 새로운 내부 `bool` 상태 변수가 추가되었습니다. 이 변수는 경매 종료 후 경매 소유자가 최고 입찰 금액을 이미 인출했는지 여부를 추적합니다.
        * `true`: 소유자가 아직 자금을 인출하지 않은 상태입니다. 
        * `false`: 소유자가 자금을 인출한 상태입니다.
    * **목적:** 경매 소유자가 최고 입찰 금액을 여러 번 인출하는 것을 방지하기 위함입니다.

2.  **경매 종료 확인 변경자 (`end_auction`)**
    * **코드:** `modifier end_auction() { require(block.timestamp > auction_end || STATE == auction_state.CANCELLED, "Auction is ongoing"); _; }`
    * **설명:** 이 새로운 변경자는 경매가 공식적으로 종료되었는지 확인합니다. 현재 블록 타임스탬프(`block.timestamp`)가 `auction_end` 시간을 지났거나, 경매 상태(`STATE`)가 명시적으로 `CANCELLED`로 설정된 경우 경매가 종료된 것으로 간주합니다. 
    * **목적:** 경매 소유자의 자금 인출과 같은 특정 작업을 경매가 종료되거나 취소된 *이후*에만 수행할 수 있도록 제한합니다. 또한, 경매 소유자가 경매를 중단했음에도 입찰이 계속 가능했던 부분을 제한합니다.

3.  **소유자 인출 여부 확인 변경자 (`withdraw_owner`)**
    * **코드:** `modifier withdraw_owner() { require(isWithdraw, "You have already withdrawn"); _; }`
    * **설명:** 이 변경자는 `isWithdraw` 상태 변수를 확인합니다. 이 변경자가 적용된 함수는 소유자가 아직 자금을 인출하지 않은 경우 (`isWithdraw`가 `true`인 경우)에만 실행될 수 있도록 보장합니다. 
    * **목적:** `isWithdraw` 변수 및 `withdrawRemainingFunds` 함수와 함께 작동하여 경매 소유자가 단 한 번만 자금을 인출할 수 있도록 규칙을 강제합니다. ("You have already withdrawn" 메시지는 이미 인출했음을 알립니다.)

4.  **최고 입찰자 확인 변경자 (`isHighestBidder`)**
    * **코드:** `modifier isHighestBidder() { require(msg.sender != highestBidder , "is the highest bidder"); _; }`
    * **설명:** 이 변경자는 현재 최고 입찰자(`highestBidder`)가 해당 함수를 실행하는 것을 방지합니다. (
    * **목적:** 주로 `withdraw` 함수에서 사용되어, 최고 입찰자가 자신의 입찰금을 인출하는 것을 막습니다. 최고 입찰자의 자금은 경매가 성공적으로 완료될 경우 경매 소유자에게 돌아가야 합니다. 다른 (최고 입찰자가 아닌) 입찰자들은 이 변경자의 영향을 받지 않고 자신의 자금을 인출할 수 있습니다.
5.  **강화된 입찰 로직 (`bid` 함수)**
    * **코드:**
        ```solidity
        // ...
        highestBid = bids[msg.sender] + msg.value; // [NEW] 최고 입찰액 계산 수정
        ```
    * **문제점:** 최고 입찰 금액보다 낮은 금액으로도 입찰 시도가 가능 , 경매 소유자가 경매를 중단했음에도 입찰이 계속 가능 (`end_auction`에서 해결)   
    * **설명:** `MyAuction`의 `bid` 함수가 다음과 같이 수정되었습니다:
        * **정확한 최고 입찰액 계산:** `highestBid`는 이제 현재 트랜잭션의 `msg.value`만이 아니라, 입찰자가 해당 경매에 입찰한 *총 누적 금액*(`bids[msg.sender] + msg.value`)으로 올바르게 업데이트됩니다. 이는 특히 입찰자가 여러 번에 걸쳐 입찰액을 높이는 경우, 실제 최고 입찰액을 정확하게 반영합니다. 
    * **목적:** 유효하지 않거나 경매를 진전시키지 못하는 입찰을 방지하고, `highestBid` 상태 변수가 항상 실제 최고 입찰 금액을 정확하게 나타내도록 보장합니다.

6.  **제어된 소유자 인출 (`withdrawRemainingFunds` 함수)**
    * **코드:**
        ```solidity
        function withdrawRemainingFunds() external override only_owner end_auction withdraw_owner {
            uint amount = bids[highestBidder];
            isWithdraw = false; // [NEW]더는 출금 못하게 막음
            // ... 이체 로직 ...
        }
        ```
    * **문제점:** 소유주가 경매 종료 여부와 상관없이 컨트랙트 내의 자금을 임의로 모두 인출 가능 
    * **설명:** 경매 소유자가 자금을 인출하는 함수가 다음과 같이 수정되었습니다:
        * **변경자 적용:** 이제 `only_owner`, `end_auction`, `withdraw_owner` 변경자를 사용합니다. 이를 통해 오직 소유자만이, 경매가 종료되거나 취소된 이후에, 그리고 **단 한 번만** 이 함수를 호출할 수 있도록 보장합니다.
        * **인출 금액:** 인출할 금액은 `highestBidder`가 입찰한 금액(`bids[highestBidder]`)으로 명확히 지정됩니다.
        * **`isWithdraw` 플래그 설정:** 중요하게도, 실제 이더 전송을 시도하기 *전에* `isWithdraw = false;`를 설정합니다. 이는 재진입(re-entrancy) 공격 가능성을 차단하고, 인출이 완료되었음을 즉시 기록하여 1회 인출 규칙을 강제합니다.
    * **목적:** 경매 소유자가 경매 종료 후 안전하고 통제된 방식으로 낙찰 금액을 정확히 한 번만 인출할 수 있는 메커니즘을 제공합니다.

7.  **제한된 입찰자 인출 (`withdraw` 함수)**
    * **코드:**
        ```solidity
        function withdraw() public override isHighestBidder returns (bool) { // [NEW] isHighestBidder 변경자 추가

        }
        ```
    * **문제점:** 최고 입찰자가 자금을 출금 가능
    * **설명:** 입찰자들이 자신의 입찰금을 회수하기 위해 사용하는 `withdraw` 함수에 `isHighestBidder` 변경자가 추가되었습니다.
    * **목적:** 최고 입찰자가 이 함수를 사용하여 자신의 입찰금을 인출하는 것을 방지합니다. 최고 입찰자가 아닌 다른 입찰자들 (또는 경매가 취소된 경우 모든 입찰자들)은 여전히 이 함수를 사용하여 예치했던 이더(Ether)를 돌려받을 수 있습니다. 
