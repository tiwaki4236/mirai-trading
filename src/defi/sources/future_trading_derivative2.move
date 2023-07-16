// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module defi::futures_trading {
    // Futures contract
    struct FutureContract {
        id: UID,
        asset_name: String,
        contract_size: u64,
        expiration_date: u64,
        price: u64,
        seller: address,
        buyer: address,
        is_closed: bool,
    }

    // Futures order
    struct Order {
        id: UID,
        asset_name: String,
        quantity: u64,
        price: u64,
        order_type: u8,
        trader: address,
        is_executed: bool,
    }

    // Position
    struct Position {
        id: UID,
        contract_id: UID,
        trader: address,
        quantity: u64,
    }

    // Derivative contract
    struct DerivativeContract {
        id: UID,
        underlying_contract_id: UID,
        multiplier: u64,
        expiration_date: u64,
        price: u64,
        seller: address,
        buyer: address,
        is_closed: bool,
    }

    // Derivative order
    struct DerivativeOrder {
        id: UID,
        underlying_order_id: UID,
        quantity: u64,
        price: u64,
        order_type: u8,
        trader: address,
        is_executed: bool,
    }

    // Derivative position
    struct DerivativePosition {
        id: UID,
        derivative_contract_id: UID,
        trader: address,
        quantity: u64,
    }

    // Arbitrage trading execution entry point
    public entry fun perform_arbitrage(contract1: FutureContract, contract2: FutureContract, buy_order: Order, sell_order: Order, ctx: &mut TxContext) {
        // Execution condition check
        assert!(!contract1.is_closed, 0);  // Check if Contract 1 is not closed
        assert!(!contract2.is_closed, 0);  // Check if Contract 2 is not closed
        assert!(buy_order.trader != sell_order.trader, 0);  // Confirm that the buyer and seller are different
        assert!(buy_order.asset_name == contract1.asset_name && sell_order.asset_name == contract2.asset_name, 0);  // Confirm that the order and contract assets have the same name
        assert!(buy_order.order_type == 1 && sell_order.order_type == 2, 0);  // Confirm that the order type is correct

        // Execute arbitrage trading
        let buy_quantity = std::cmp::min(buy_order.quantity, sell_order.quantity);  // Trading quantity is the minimum value of the order
        let buy_amount = buy_quantity * contract1.price;  // Trading amount in Contract 1
        let sell_amount = buy_quantity * contract2.price;  // Trading amount in Contract 2

        // Calculation of trading amount
        let total_amount = sell_amount - buy_amount;

        // Transfer the trading amount from the seller to the buyer
        transfer::transfer(Balance<SUI>::from(total_amount), buy_order.trader);

        // Adjust the position quantity
        let buyer_position = Position::get_by_trader_and_contract(buy_order.trader, contract1.id);
        let seller_position = Position::get_by_trader_and_contract(sell_order.trader, contract2.id);

        assert!(buyer_position.is_some(), 0);  // Confirm the existence of the buyer's position
        assert!(seller_position.is_some(), 0);  // Confirm the existence of the seller's position

        let mut buyer_position = buyer_position.unwrap();
        let mut seller_position = seller_position.unwrap();

        buyer_position.quantity += buy_quantity;
        seller_position.quantity -= buy_quantity;

        Position::update(buyer_position.id, buyer_position);
        Position::update(seller_position.id, seller_position);

        // Adjust the quantity of the order
        buy_order.quantity -= buy_quantity;
        sell_order.quantity -= buy_quantity;

        Order::update(buy_order.id, buy_order);
        Order::update(sell_order.id, sell_order);

        // Contract closure check and settlement
        if buy_order.quantity == 0 {
            // If the buyer's order is completely closed, close the contract and proceed with the settlement process
            contract1.is_closed = true;
            FutureContract::update(contract1.id, contract1);
            settle_contract(contract1.id, ctx);
        }

        if sell_order.quantity == 0 {
            // If the seller's order is completely closed, close the contract and proceed with the settlement process
            contract2.is_closed = true;
            FutureContract::update(contract2.id, contract2);
            settle_contract(contract2.id, ctx);
        }
    }

    // Entry point to execute arbitrage trading
    public entry fun execute_arbitrage(contract1_id: UID, contract2_id: UID, buy_order_id: UID, sell_order_id: UID, ctx: &mut TxContext) {
        let contract1 = FutureContract::get(contract1_id);
        let contract2 = FutureContract::get(contract2_id);
        let buy_order = Order::get(buy_order_id);
        let sell_order = Order::get(sell_order_id);

        assert!(contract1.is_some(), 0);  // Check if Contract 1 exists
        assert!(contract2.is_some(), 0);  // Check if Contract 2 exists
        assert!(buy_order.is_some(), 0);  // Confirm the existence of a buy order
        assert!(sell_order.is_some(), 0);  // Confirm the existence of a sell order

        perform_arbitrage(contract1.unwrap(), contract2.unwrap(), buy_order.unwrap(), sell_order.unwrap(), ctx);
    }

    // Order cancellation entry point
    public entry fun cancel_order(order_id: UID, ctx: &mut TxContext) {
        let order = Order::get(order_id);
        assert!(order.is_some(), 0);  // Confirm the existence of an order

        let mut order = order.unwrap();
        assert!(order.trader == tx_context::sender(ctx), 0);  // Confirm that the sender is the owner of the order
        assert!(!order.is_executed, 0);  // Confirm that the order has not been executed

        order.is_executed = true;
        Order::update(order_id, order);
    }

    // Derivative order cancellation entry point
    public entry fun cancel_derivative_order(order_id: UID, ctx: &mut TxContext) {
        let order = DerivativeOrder::get(order_id);
        assert!(order.is_some(), 0);  // Confirm the existence of an order

        let mut order = order.unwrap();
        assert!(order.trader == tx_context::sender(ctx), 0);  // Confirm that the sender is the owner of the order
        assert!(!order.is_executed, 0);  // Confirm that the order has not been executed

        order.is_executed = true;
        DerivativeOrder::update(order_id, order);
    }

    // Futures contract creation entry point
    public entry fun create_future_contract(asset_name: String, contract_size: u64, expiration_date: u64, price: u64, ctx: &mut TxContext) {
        let contract = FutureContract {
            id: object::new(ctx),
            asset_name,
            contract_size,
            expiration_date,
            price,
            seller: tx_context::sender(ctx),
            buyer: address(0),
            is_closed: false,
        };
        transfer::transfer(contract, tx_context::sender(ctx));
    }

    // Derivative contract creation entry point
    public entry fun create_derivative_contract(underlying_contract_id: UID, multiplier: u64, expiration_date: u64, price: u64, ctx: &mut TxContext) {
        let contract = DerivativeContract {
            id: object::new(ctx),
            underlying_contract_id,
            multiplier,
            expiration_date,
            price,
            seller: tx_context::sender(ctx),
            buyer: address(0),
            is_closed: false,
        };
        transfer::transfer(contract, tx_context::sender(ctx));
    }

    // Futures order creation entry point
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

    // Derivative order creation entry point
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

    // Get all open orders
    public fun get_open_orders(trader: address): Vec<Order> {
        let all_orders = Order::get_all();
        let mut open_orders = Vec::new();

        for order in all_orders {
            if order.trader == trader && !order.is_executed {
                open_orders.push(order);
            }
        }

        open_orders
    }

   // Get all open derivative orders
    public fun get_open_derivative_orders(trader: address): Vec<DerivativeOrder> {
        let all_orders = DerivativeOrder::get_all();
        let mut open_orders = Vec::new();

        for order in all_orders {
            if order.trader == trader && !order.is_executed {
                open_orders.push(order);
            }
        }

        open_orders
    }

   // Futures contract closure check and settlement process
    private fun settle_contract(contract_id: UID, ctx: &mut TxContext) {
        let contract = FutureContract::get(contract_id);
        assert!(contract.is_closed, 0);  // Confirm that the contract is closed

        let seller = contract.seller;
        let buyer = contract.buyer;
        let contract_size = contract.contract_size;
        let price = contract.price;

        // Return collateral to the seller
        let deposit = contract_size * price;
        transfer::transfer(Balance<SUI>::from(deposit), seller);

        // Settle the position
        if buyer != address(0) {
            let position = Position {
                id: object::new(ctx),
                contract_id,
                trader: buyer,
                quantity: contract_size,
            };
            transfer::transfer(position, buyer);
        }
    }

    // Derivative contract closure check and settlement process
    private fun settle_derivative_contract(derivative_contract_id: UID, ctx: &mut TxContext) {
        let derivative_contract = DerivativeContract::get(derivative_contract_id);
        assert!(derivative_contract.is_closed, 0);  // Confirm that the contract is closed

        let seller = derivative_contract.seller;
        let buyer = derivative_contract.buyer;
        let multiplier = derivative_contract.multiplier;
        let price = derivative_contract.price;

        // Return collateral to the seller
        let deposit = multiplier * price;
        transfer::transfer(Balance<SUI>::from(deposit), seller);

        // Settle the position
        if buyer != address(0) {
            let position = DerivativePosition {
                id: object::new(ctx),
                derivative_contract_id,
                trader: buyer,
                quantity: multiplier,
            };
            transfer::transfer(position, buyer);
        }
    }

    // Entry point to get all futures contracts
    public fun get_future_contracts(): Vec<FutureContract> {
        FutureContract::get_all()
    }

    // Entry point to get all futures orders
    public fun get_orders(): Vec<Order> {
        Order::get_all()
    }

    // Entry point to get all derivative contracts
    public fun get_derivative_contracts(): Vec<DerivativeContract> {
        DerivativeContract::get_all()
    }

    // Entry point to get all derivative orders
    public fun get_derivative_orders(): Vec<DerivativeOrder> {
        DerivativeOrder::get_all()
    }
}
