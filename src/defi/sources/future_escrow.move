//Reference Codes: https://github.com/MystenLabs/sui/tree/main/sui_programmability/examples

// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// An escrow for futures trading
module defi::futures_escrow {
    use std::option::{Self, Option};

    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    /// An object held in escrow for futures trading
    struct FuturesEscrowedObj<T: key + store, phantom UnderlyingT: key + store> has key, store {
        id: UID,
        /// owner of the escrowed object
        creator: address,
        /// intended recipient of the escrowed object
        recipient: address,
        /// ID of the underlying asset to be delivered
        underlying_asset_id: ID,
        /// the quantity of the underlying asset to be delivered
        underlying_quantity: u64,
        /// the escrowed object
        escrowed: Option<T>,
    }

    // Error codes
    /// An attempt to cancel escrow by a different user than the owner
    const EWrongOwner: u64 = 0;
    /// Exchange by a different user than the `recipient` of the escrowed object
    const EWrongRecipient: u64 = 1;
    /// The escrow has already been exchanged or cancelled
    const EAlreadyExchangedOrCancelled: u64 = 2;

    /// Create an escrow for futures trading
    public fun create<T: key + store, UnderlyingT: key + store>(
        recipient: address,
        underlying_asset_id: ID,
        underlying_quantity: u64,
        escrowed_item: T,
        ctx: &mut TxContext
    ) {
        let creator = tx_context::sender(ctx);
        let id = object::new(ctx);
        let escrowed = option::some(escrowed_item);
        transfer::public_share_object(
            FuturesEscrowedObj<T, UnderlyingT> {
                id, creator, recipient, underlying_asset_id, underlying_quantity, escrowed
            }
        );
    }

    /// The `recipient` of the escrow can settle the futures trade by delivering the underlying asset
    public entry fun settle_futures_trade<T: key + store, UnderlyingT: key + store>(
        underlying_asset: UnderlyingT,
        escrow: &mut FuturesEscrowedObj<T, UnderlyingT>,
        ctx: &TxContext
    ) {
        assert!(option::is_some(&escrow.escrowed), EAlreadyExchangedOrCancelled);
        let escrowed_item = option::extract<T>(&mut escrow.escrowed);
        assert!(&tx_context::sender(ctx) == &escrow.recipient, EWrongRecipient);
        assert!(object::borrow_id(&underlying_asset) == &escrow.underlying_asset_id);
        // Perform the settlement by transferring the underlying asset to the creator
        transfer::public_transfer(underlying_asset, escrow.creator);
        // Transfer the escrowed item to the recipient
        transfer::public_transfer(escrowed_item, tx_context::sender(ctx));
    }

    /// The `creator` can cancel the escrow and get back the escrowed item
    public entry fun cancel<T: key + store, UnderlyingT: key + store>(
        escrow: &mut FuturesEscrowedObj<T, UnderlyingT>,
        ctx: &TxContext
    ) {
        assert!(&tx_context::sender(ctx) == &escrow.creator, EWrongOwner);
        assert!(option::is_some(&escrow.escrowed), EAlreadyExchangedOrCancelled);
        transfer::public_transfer(option::extract<T>(&mut escrow.escrowed), escrow.creator);
    }
}