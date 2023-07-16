// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

// Futures Trading (Derivative Function Addition)

module tutorial::futures_trading {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct FutureContract has key {
        id: UID,
        asset_name: String,
        contract_size: u64,
        expiration_date: u64,
        price: u64,
        seller: address,
        buyer: address,
        is_closed: bool,
    }

    struct Order has key {
        id: UID,
        asset_name: String,
        quantity: u64,
        price: u64,
        order_type: u8,  // 0 for buy, 1 for sell
        trader: address,
        is_executed: bool,
    }

    struct DerivativeContract has key {
        id: UID,
        underlying_contract_id: UID,
        multiplier: u64,
        expiration_date: u64,
        price: u64,
        seller: address,
        buyer: address,
        is_closed: bool,
    }

    struct DerivativeOrder has key {
        id: UID,
        underlying_order_id: UID,
        quantity: u64,
        price: u64,
        order_type: u8,  // 0 for buy, 1 for sell
        trader: address,
        is_executed: bool,
    }

    public entry fun create_future_contract(asset_name: String, contract_size: u64, expiration_date: u64, price: u64, ctx: &mut TxContext) {
        let contract = FutureContract {
            id: object::new(ctx),
            asset_name,
            contract_size,
            expiration_date,
            price,
            seller: tx_context::sender(ctx),
            buyer: address(0),  // Initialize buyer as empty address
            is_closed: false,
        };
        transfer::transfer(contract, tx_context::sender(ctx));
    }

    public entry fun create_derivative_contract(underlying_contract_id: UID, multiplier: u64, expiration_date: u64, price: u64, ctx: &mut TxContext) {
        let contract = DerivativeContract {
            id: object::new(ctx),
            underlying_contract_id,
            multiplier,
            expiration_date,
            price,
            seller: tx_context::sender(ctx),
            buyer: address(0),  // Initialize buyer as empty address
            is_closed: false,
        };
        transfer::transfer(contract, tx_context::sender(ctx));
    }

    public entry fun place_order(asset_name: String, quantity: u64, price: u64, order_type: u8, ctx: &mut TxContext) {
        let order = Order {
            id: object::new(ctx),
            asset_name,
            quantity,
            price,
            order_type,
            trader: tx_context::sender(ctx),
            is_executed: false,
        };
        transfer::transfer(order, tx_context::sender(ctx));
    }

    public entry fun place_derivative_order(underlying_order_id: UID, quantity: u64, price: u64, order_type: u8, ctx: &mut TxContext) {
        let order = DerivativeOrder {
            id: object::new(ctx),
            underlying_order_id,
            quantity,
            price,
            order_type,
            trader: tx_context::sender(ctx),
            is_executed: false,
        };
        transfer::transfer(order, tx_context::sender(ctx));
    }

    public entry fun execute_trade(contract: FutureContract, buy_order: Order, sell_order: Order, ctx: &mut TxContext) {
        assert!(contract.expiration_date > ctx.block_timestamp, 0);  // Check if contract is not expired
        assert!(buy_order.order_type == 0 && sell_order.order_type == 1, 0);  // Check if buy and sell orders match
        assert!(buy_order.asset_name == contract.asset_name && sell_order.asset_name == contract.asset_name, 0);  // Check if asset names match
        assert!(buy_order.quantity == sell_order.quantity, 0);  // Check if quantities match

        // Perform the trade
        transfer::transfer(contract.price * buy_order.quantity, buy_order.trader);
        transfer::transfer(contract.price * sell_order.quantity, sell_order.trader);

        // Update the contract details
        contract.buyer = buy_order.trader;

        // Set orders as executed
        buy_order.is_executed = true;
        sell_order.is_executed = true;

        // Check if the contract should be closed
        check_contract_closure(contract);
    }

    public entry fun execute_derivative_trade(derivative_contract: DerivativeContract, derivative_buy_order: DerivativeOrder, derivative_sell_order: DerivativeOrder, ctx: &mut TxContext) {
        assert!(derivative_contract.expiration_date > ctx.block_timestamp, 0);  // Check if contract is not expired
        assert!(derivative_buy_order.order_type == 0 && derivative_sell_order.order_type == 1, 0);  // Check if buy and sell orders match
        assert!(derivative_contract.underlying_contract_id == derivative_buy_order.underlying_order_id && derivative_contract.underlying_contract_id == derivative_sell_order.underlying_order_id, 0);  // Check if underlying contracts match
        assert!(derivative_buy_order.quantity == derivative_sell_order.quantity, 0);  // Check if quantities match

        // Perform the trade
        let underlying_contract = FutureContract::get(derivative_contract.underlying_contract_id).unwrap();
        let trade_value = derivative_contract.multiplier * derivative_buy_order.quantity * underlying_contract.price;
        transfer::transfer(trade_value, derivative_buy_order.trader);
        transfer::transfer(trade_value, derivative_sell_order.trader);

        // Update the derivative contract details
        derivative_contract.buyer = derivative_buy_order.trader;

        // Set orders as executed
        derivative_buy_order.is_executed = true;
        derivative_sell_order.is_executed = true;

        // Check if the derivative contract should be closed
        check_derivative_contract_closure(derivative_contract);
    }

    private fun check_contract_closure(contract: FutureContract) {
        let buy_order = Order::get(contract.id, 0); // Find the buy order by order type (0)
        let sell_order = Order::get(contract.id, 1); // Find the sell order by order type (1)

        if (buy_order.is_some() && sell_order.is_some()) {
            let buy_order = buy_order.unwrap();
            let sell_order = sell_order.unwrap();

            if (buy_order.is_executed && sell_order.is_executed) {
                contract.is_closed = true;
                FutureContract::update(contract.id, contract);
                settle_contract(contract);
            }
        }
    }

    private fun check_derivative_contract_closure(derivative_contract: DerivativeContract) {
        let derivative_buy_order = DerivativeOrder::get(derivative_contract.id, 0); // Find the buy order by order type (0)
        let derivative_sell_order = Der
