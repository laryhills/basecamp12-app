use contracts::Counter::Counter::FELT_STRK_CONTRACT;
use contracts::Counter::{
    Counter, ICounterDispatcher, ICounterDispatcherTrait, ICounterSafeDispatcher,
    ICounterSafeDispatcherTrait,
};
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::EventSpyAssertionsTrait;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, spy_events, start_cheat_caller_address,
    stop_cheat_caller_address,
};

use starknet::{ContractAddress};


const ZERO_COUNT: u32 = 0;
const STRK_AMOUNT: u256 = 5000000000000000000;
const WIN_NUMBER: u32 = 10;


fn OWNER() -> ContractAddress {
    'OWNER'.try_into().unwrap()
}

fn USER_1() -> ContractAddress {
    'USER_1'.try_into().unwrap()
}

fn STRK() -> ContractAddress {
    FELT_STRK_CONTRACT.try_into().unwrap()
}

pub const STRK_TOKEN_ADDRESS: felt252 =
    0x069a62bdc4652444f41cdfab856b60e3a0907542cda46c9844fedc08699ef983;

fn STRK_TOKEN_HOLDER() -> ContractAddress {
    STRK_TOKEN_ADDRESS.try_into().unwrap()
}

fn __deploy__(
    init_value: u32,
) -> (ICounterDispatcher, IOwnableDispatcher, ICounterSafeDispatcher, IERC20Dispatcher) {
    let contract_class = declare("Counter").expect('failed to declare').contract_class();

    let mut calldata: Array<felt252> = array![];
    // ZERO_COUNT.serialize(ref calldata);
    init_value.serialize(ref calldata);

    OWNER().serialize(ref calldata);

    let (contract_address, _) = contract_class.deploy(@calldata).expect('failed to deploy');

    let counter = ICounterDispatcher { contract_address };
    let ownable = IOwnableDispatcher { contract_address };
    let safe_dispatcher = ICounterSafeDispatcher { contract_address };
    let strk_token = IERC20Dispatcher { contract_address: STRK() };

    transfer_strk(STRK_TOKEN_HOLDER(), contract_address, STRK_AMOUNT);
    // start_cheat_caller_address(STRK(), STRK_TOKEN_HOLDER());
    // strk_token.transfer(contract_address, STRK_AMOUNT);
    // stop_cheat_caller_address(STRK());

    (counter, ownable, safe_dispatcher, strk_token)
}

fn get_strk_token_balance(account: ContractAddress) -> u256 {
    IERC20Dispatcher { contract_address: STRK() }.balance_of(account)
}

fn transfer_strk(caller: ContractAddress, recipient: ContractAddress, amount: u256) {
    start_cheat_caller_address(STRK(), caller);
    let token_dispatcher = IERC20Dispatcher { contract_address: STRK() };
    token_dispatcher.transfer(recipient, amount);
    stop_cheat_caller_address(STRK());
}

fn approve_strk(owner: ContractAddress, spender: ContractAddress, amount: u256) {
    start_cheat_caller_address(STRK(), owner);
    let token_dispatcher = IERC20Dispatcher { contract_address: STRK() };
    token_dispatcher.approve(spender, amount);
    stop_cheat_caller_address(STRK());
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_counter_deployment() {
    let (counter, ownable, _, _) = __deploy__(ZERO_COUNT);

    let count_1 = counter.get_counter();

    assert(count_1 == ZERO_COUNT, 'count not set');
    assert(ownable.owner() == OWNER(), 'owner not set');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_increase_counter() {
    let (counter, _, _, _) = __deploy__(ZERO_COUNT);

    let count_1 = counter.get_counter();

    assert(count_1 == ZERO_COUNT, 'count not set');

    counter.increase_counter();

    let count_2 = counter.get_counter();
    assert(count_2 == count_1 + 1, 'invalid count');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_emitted_increase_event() {
    let (counter, _, _, _) = __deploy__(ZERO_COUNT);
    let mut spy = spy_events();

    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.increase_counter();
    stop_cheat_caller_address(counter.contract_address);
    spy
        .assert_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Increased(Counter::Increased { account: USER_1() }),
                ),
            ],
        );

    spy
        .assert_not_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Decreased(Counter::Decreased { account: USER_1() }),
                ),
            ],
        );
}


#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_increase_counter_contract_transfers_strk_to_caller_when_count_is_a_win_number() {
    let (counter, _, _, _) = __deploy__(9);

    let count_1 = counter.get_counter();
    assert(count_1 == 9, 'count not set');

    let counter_strk_balance_1 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_1 == STRK_AMOUNT, 'invalid counter balance');

    // ....
    let user1_strk_balance_1: u256 = get_strk_token_balance(USER_1());
    assert(user1_strk_balance_1 == 0, 'invalid user balance');

    start_cheat_caller_address(counter.contract_address, USER_1());

    start_cheat_caller_address(STRK(), counter.contract_address);

    let win_number: u32 = counter.get_win_number();
    assert(win_number == WIN_NUMBER, 'invalid win number');

    counter.increase_counter();

    stop_cheat_caller_address(counter.contract_address);
    stop_cheat_caller_address(STRK());

    let count_2 = counter.get_counter();
    assert(count_2 == 10, 'count 2 not set');

    let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == 0, 'invalid counter_2 STRK balance');

    let user1_strk_balance_2: u256 = get_strk_token_balance(USER_1());
    assert(user1_strk_balance_2 == STRK_AMOUNT, 'strk not transferred');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_increase_counter_contract_does_not_transfers_strk_to_caller_when_count_is_a_win_number_and_has_zero_strk() {
    let (counter, _, _, _) = __deploy__(9);

    let count_1 = counter.get_counter();
    assert(count_1 == 9, 'count not set');

    let counter_strk_balance_1 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_1 == STRK_AMOUNT, 'invalid counter balance');

    let owner_strk_balance_1: u256 = get_strk_token_balance(USER_1());
    assert(owner_strk_balance_1 == 0, 'invalid owner balance');

    // transfer out all 5 STRK tokesn to OWNER
    transfer_strk(counter.contract_address, OWNER(), STRK_AMOUNT);

    let counter_strk_balance_after_trf_to_owner = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_after_trf_to_owner == 0, 'not transferred to owner');

    start_cheat_caller_address(counter.contract_address, USER_1());

    let win_number: u32 = counter.get_win_number();
    assert(win_number == WIN_NUMBER, 'invalid win number');

    counter.increase_counter();

    stop_cheat_caller_address(counter.contract_address);

    let count_2 = counter.get_counter();
    assert(count_2 == 10, 'count 2 not set');

    let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == 0, 'strk bal should unchanged');

    let user1_strk_balance_1: u256 = get_strk_token_balance(USER_1());
    assert(user1_strk_balance_1 == 0, 'strk bal should not increase');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
#[feature("safe_dispatcher")]
fn test_safe_panic_decrease_counter() {
    let (counter, _, safe_dispatcher, _) = __deploy__(ZERO_COUNT);

    assert(counter.get_counter() == ZERO_COUNT, 'invalid count');

    match safe_dispatcher.decrease_counter() {
        Result::Ok(_) => panic!("cannot decrease 0"),
        Result::Err(e) => assert(*e[0] == 'Decreasing Empty counter', *e.at(0)),
    }
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
#[should_panic(expected: 'Decreasing Empty counter')]
fn test_panic_decrease_counter() {
    let (counter, _, _, _) = __deploy__(ZERO_COUNT);

    assert(counter.get_counter() == ZERO_COUNT, 'invalid count');

    counter.decrease_counter()
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_successful_decrease_counter() {
    let (counter, _, _, _) = __deploy__(5);
    let count_1 = counter.get_counter();

    assert(count_1 == 5, 'invalid count');

    counter.decrease_counter();

    let count_2 = counter.get_counter();
    assert(count_2 == count_1 - 1, 'invalid decrease count');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_emitted_decrease_event() {
    let (counter, _, _, _) = __deploy__(5);
    let mut spy = spy_events();

    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.decrease_counter();
    stop_cheat_caller_address(counter.contract_address);
    spy
        .assert_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Decreased(Counter::Decreased { account: USER_1() }),
                ),
            ],
        );

    spy
        .assert_not_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Increased(Counter::Increased { account: USER_1() }),
                ),
            ],
        );
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
#[feature("safe_dispatcher")]
fn test_safe_panic_reset_counter_by_no_owner() {
    let (counter, _, safe_dispatcher, _) = __deploy__(ZERO_COUNT);

    assert(counter.get_counter() == ZERO_COUNT, 'invalid count');

    start_cheat_caller_address(counter.contract_address, USER_1());

    match safe_dispatcher.reset_counter() {
        Result::Ok(_) => panic!("cannot reset"),
        Result::Err(e) => assert(*e[0] == 'Caller is not the owner', *e.at(0)),
    }
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_successful_reset_counter() {
    let (counter, _, _, strk_token) = __deploy__(5);

    // spy for tracking emitted event
    let mut spy = spy_events();

    // 10 strk
    let test_strk_amount: u256 = 10000000000000000000;
    let count_1 = counter.get_counter();

    assert(count_1 == 5, 'invalid count');

    // initiate token approve by USER 1, for counter contranct spend action
    approve_strk(USER_1(), counter.contract_address, test_strk_amount);

    let counter_allowance = strk_token.allowance(USER_1(), counter.contract_address);
    assert(counter_allowance == test_strk_amount, 'failed to approve');

    let strk_holder_balance: u256 = get_strk_token_balance(STRK_TOKEN_HOLDER());
    assert(strk_holder_balance > test_strk_amount, 'insuffience STRK');

    // transfer form provider to USER 1
    transfer_strk(STRK_TOKEN_HOLDER(), USER_1(), test_strk_amount);

    // validate token transfer TOKEN_HOLDER -> USER 1
    let user1_strk_balance_1: u256 = get_strk_token_balance(USER_1());
    assert(user1_strk_balance_1 == test_strk_amount, 'strk not transferred');

    // check counter contract balance
    let counter_strk_balance_1 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_1 == STRK_AMOUNT, 'invalid counter balance');

    // sim txm from USER_1
    start_cheat_caller_address(counter.contract_address, USER_1());

    // reset
    counter.reset_counter();

    stop_cheat_caller_address(counter.contract_address);
    
    let count_2 = counter.get_counter();
    assert(count_2 == 0, 'counter not reset');

    // validate counter contract received strk tokens
    let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == STRK_AMOUNT + STRK_AMOUNT, 'no strk transferes');

    // validate token transfer TOKEN_HOLDER -> USER 1
    let user1_strk_balance_2: u256 = get_strk_token_balance(USER_1());
    assert(user1_strk_balance_2 == test_strk_amount - STRK_AMOUNT, 'strk not deducted');

    // asset Reset Event
    spy
        .assert_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Reset(Counter::Reset { account: USER_1() }),
                ),
            ],
        );

    // asset no increased event was emitted
    spy
        .assert_not_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Increased(Counter::Increased { account: USER_1() }),
                ),
            ],
        );
}
