// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module defi::futures_pool {
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Supply, Balance};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::math;
    use sui::tx_context::{Self, TxContext};

    /// For when supplied Coin is zero.
    const EZeroAmount: u64 = 0;

    /// For when pool fee is set incorrectly.
    /// Allowed values are: [0-10000).
    const EWrongFee: u64 = 1;

    /// For when someone tries to swap in an empty pool.
    const EReservesEmpty: u64 = 2;

    /// For when initial LSP amount is zero.
    const EShareEmpty: u64 = 3;

    /// For when someone attempts to add more liquidity than u128 Math allows.
    const EPoolFull: u64 = 4;

    /// The integer scaling setting for fees calculation.
    const FEE_SCALING: u128 = 10000;

    /// The max value that can be held in one of the Balances of
    /// a Pool. U64 MAX / FEE_SCALING
    const MAX_POOL_VALUE: u64 = {
        18446744073709551615 / 10000
    };

    /// The Pool token that will be used to mark the pool share
    /// of a liquidity provider. The first type parameter stands
    /// for the witness type of a pool. The seconds is for the
    /// coin held in the pool.
    struct LSP<phantom P, phantom T> has drop {}

    /// The pool with exchange.
    ///
    /// - `fee_percent` should be in the range: [0-10000), meaning
    /// that 1000 is 100% and 1 is 0.1%
    struct Pool<phantom P, phantom T> has key {
        id: UID,
        sui: Balance<SUI>,
        token: Balance<T>,
        lsp_supply: Supply<LSP<P, T>>,
        /// Fee Percent is denominated in basis points.
        fee_percent: u64
    }

    #[allow(unused_function)]
    /// Module initializer is empty - to publish a new Pool one has
    /// to create a type which will mark LSPs.
    fun init(_: &mut TxContext) {}

    /// Create new `Pool` for token `T`. Each Pool holds a `Coin<T>`
    /// and a `Coin<SUI>`. Swaps are available in both directions.
    ///
    /// Share is calculated based on Uniswap's constant product formula:
    ///  liquidity = sqrt( X * Y )
    public fun create_pool<P: drop, T>(
        _: P,
        token: Coin<T>,
        sui: Coin<SUI>,
        fee_percent: u64,
        ctx: &mut TxContext
    ): Coin<LSP<P, T>> {
        let sui_amt = coin::value(&sui);
        let tok_amt = coin::value(&token);

        assert!(sui_amt > 0 && tok_amt > 0, EZeroAmount);
        assert!(sui_amt < MAX_POOL_VALUE && tok_amt < MAX_POOL_VALUE, EPoolFull);
        assert!(fee_percent >= 0 && fee_percent < 10000, EWrongFee);

        // Initial share of LSP is the sqrt(a) * sqrt(b)
        let share = math::sqrt(sui_amt) * math::sqrt(tok_amt);
        let lsp_supply = balance::create_supply(LSP<P, T> {});
        let lsp = balance::increase_supply(&mut lsp_supply, share);

        transfer::share_object(Pool {
            id: object::new(ctx),
            token: coin::into_balance(token),
            sui: coin::into_balance(sui),
            lsp_supply,
            fee_percent
        });

        coin::from_balance(lsp, ctx)
    }

    /// Entrypoint for the `create_futures_contract` method. Creates a new futures contract.
    ///
    /// `expiration`: Expiration date of the futures contract.
    /// `quantity`: Quantity of the underlying asset in the contract.
    /// `price`: Price of the futures contract.
    /// `ctx`: Transaction context.
    ///
    /// Returns the ID of the created futures contract.
    entry fun create_futures_contract_<P: drop, T>(
        pool: &mut Pool<P, T>,
        expiration: u64,
        quantity: u64,
        price: u64,
        ctx: &mut TxContext
    ): UID {
        let contract_id = object::new(ctx);
        // Store the contract details in a contract storage struct
        let contract = Contract {
            id: contract_id,
            expiration,
            quantity,
            price
        };
        storage::put(contract_id, contract);
        // Emit an event to notify contract creation
        emit ContractCreated(contract_id);
        contract_id
    }

    /// Entrypoint for the `execute_futures_contract` method. Executes a futures contract.
    ///
    /// `contract_id`: ID of the futures contract to execute.
    /// `quantity`: Quantity of the underlying asset to settle.
    /// `ctx`: Transaction context.
    entry fun execute_futures_contract_<P: drop, T>(
        pool: &mut Pool<P, T>,
        contract_id: UID,
        quantity: u64,
        ctx: &mut TxContext
    ) {
        // Get the contract details from contract storage
        let contract = storage::get(contract_id);
        assert!(contract.expiration > current_time(), EContractExpired);
        // Calculate the settlement amount based on the contract's price and quantity
        let settlement_amount = contract.price * quantity;
        // Execute the settlement by swapping the settlement amount of SUI for the underlying asset
        let settlement_token = swap_sui(pool, mint<SUI>(settlement_amount, ctx), ctx);
        // Transfer the settled asset to the contract holder
        transfer::public_transfer(settlement_token, contract_holder(contract_id));
        // Emit an event to notify contract execution
        emit ContractExecuted(contract_id, quantity);
        // Destroy the contract object
        storage::remove(contract_id);
    }

    /// Entrypoint for the `cancel_futures_contract` method. Cancels a futures contract.
    ///
    /// `contract_id`: ID of the futures contract to cancel.
    /// `ctx`: Transaction context.
    entry fun cancel_futures_contract_<P: drop, T>(
        pool: &mut Pool<P, T>,
        contract_id: UID,
        ctx: &mut TxContext
    ) {
        // Get the contract details from contract storage
        let contract = storage::get(contract_id);
        assert!(contract.expiration > current_time(), EContractExpired);
        // Return the deposited quantity of the underlying asset to the contract holder
        transfer::public_transfer(mint<T>(contract.quantity, ctx), contract_holder(contract_id));
        // Emit an event to notify contract cancellation
        emit ContractCancelled(contract_id);
        // Destroy the contract object
        storage::remove(contract_id);
    }
}