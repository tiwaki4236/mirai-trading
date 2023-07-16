// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module defi::futures_trading {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct FuturesContract<T: key + store> has key, store {
        id: UID,
        buyer: address,
        seller: address,
        collateral: Balance<Coin<T>>,
        expiration: u64,
        executed: bool,
    }

    struct FuturesEscrow<T: key + store> has key, store {
        id: UID,
        contract_id: ID,
        collateral: Coin<T>,
    }

    struct FlashLender<phantom T> has key {
        id: UID,
        to_lend: Balance<Coin<T>>,
        fee: u64,
    }

    struct Receipt<phantom T> {
        flash_lender_id: ID,
        repay_amount: u64,
    }

    struct AdminCap has key, store {
        id: UID,
        flash_lender_id: ID,
    }

    const ELoanTooLarge: u64 = 0;
    const EInvalidRepaymentAmount: u64 = 1;
    const ERepayToWrongLender: u64 = 2;
    const EAdminOnly: u64 = 3;
    const EWithdrawTooLarge: u64 = 4;

    // Creating a futures contract
    public fun create_contract<T>(
        buyer: address,
        seller: address,
        collateral: Coin<T>,
        expiration: u64,
        ctx: &mut TxContext
    ): FuturesContract<T> {
        let id = object::new(ctx);
        let contract = FuturesContract {
            id,
            buyer,
            seller,
            collateral: Balance::new(collateral),
            expiration,
            executed: false,
        };
        transfer::public_transfer(contract, ctx.sender());
        contract
    }

    // Creating a flash lender for collateral funds
    public fun new_flash_lender<T>(to_lend: Balance<Coin<T>>, fee: u64, ctx: &mut TxContext): AdminCap {
        let id = object::new(ctx);
        let flash_lender_id = object::uid_to_inner(&id);
        let flash_lender = FlashLender { id, to_lend, fee };
        transfer::share_object(flash_lender);

        AdminCap { id: object::new(ctx), flash_lender_id }
    }

    // Borrowing collateral from flash lender
    public fun borrow_collateral<T>(
        self: &mut FlashLender<T>,
        amount: u64,
        ctx: &mut TxContext
    ): (Coin<T>, Receipt<T>) {
        let to_lend = &mut self.to_lend;
        assert!(balance::value(to_lend) >= amount, ELoanTooLarge);
        let collateral = coin::take(to_lend, amount, ctx);
        let repay_amount = amount + self.fee;
        let receipt = Receipt { flash_lender_id: object::id(self), repay_amount };

        (collateral, receipt)
    }

    // Repaying borrowed collateral to flash lender
    public fun repay_collateral<T>(
        self: &mut FlashLender<T>,
        payment: Coin<T>,
        receipt: Receipt<T>
    ) {
        let Receipt { flash_lender_id, repay_amount } = receipt;
        assert!(object::id(self) == flash_lender_id, ERepayToWrongLender);
        assert!(coin::value(&payment) == repay_amount, EInvalidRepaymentAmount);

        coin::put(&mut self.to_lend, payment);
    }

    // Withdrawing collateral from futures escrow
    public fun withdraw_collateral<T>(
        escrow: &mut FuturesEscrow<T>,
        admin_cap: &AdminCap,
        amount: u64,
        ctx: &mut TxContext
    ) -> Coin<T> {
        check_admin(escrow, admin_cap);

        let collateral = coin::take(&mut escrow.collateral, amount, ctx);
        collateral
    }

    // Depositing collateral to futures escrow
    public fun deposit_collateral<T>(
        escrow: &mut FuturesEscrow<T>,
        admin_cap: &AdminCap,
        collateral: Coin<T>
    ) {
        check_admin(escrow, admin_cap);
        coin::put(&mut escrow.collateral, collateral);
    }

    // Checking admin permissions
    fun check_admin<T>(self: &FuturesEscrow<T>, admin_cap: &AdminCap) {
        assert!(object::borrow_id(self) == &admin_cap.flash_lender_id, EAdminOnly);
    }

    // Checking contract expiration
    public fun is_expired<T>(contract: &FuturesContract<T>, current_time: u64) -> bool {
        contract.expiration <= current_time
    }

    // Executing a futures contract
    public fun execute_contract<T>(
        contract: &mut FuturesContract<T>,
        buyer_payment: Coin<T>,
        seller_payment: Coin<T>,
        buyer_admin_cap: &AdminCap,
        seller_admin_cap: &AdminCap,
        buyer_escrow: &mut FuturesEscrow<T>,
        seller_escrow: &mut FuturesEscrow<T>,
        ctx: &mut TxContext
    ) {
        check_admin(buyer_escrow, buyer_admin_cap);
        check_admin(seller_escrow, seller_admin_cap);

        assert!(!contract.executed, "Contract has already been executed");

        // Transfer collateral from buyer's escrow to seller's escrow
        coin::transfer(&mut buyer_escrow.collateral, &mut seller_escrow.collateral, ctx);

        // Transfer payments from buyer to seller and vice versa
        coin::transfer(buyer_payment, seller_admin_cap, ctx);
        coin::transfer(seller_payment, buyer_admin_cap, ctx);

        // Mark contract as executed
        contract.executed = true;
    }

    // Reading contract details
    public fun get_contract_details<T>(
        contract: &FuturesContract<T>
    ) -> (address, address, Balance<Coin<T>>, u64, bool) {
        (
            contract.buyer,
            contract.seller,
            contract.collateral.clone(),
            contract.expiration,
            contract.executed,
        )
    }
}
