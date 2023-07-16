// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0


module defi::shared_escrow {
    use std::option::{Option, Some, None};
    use std::vec::Vec;
    use std::time::Duration;

    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct EscrowedObj<T: key + store, ExchangeForT: key + store> has key, store {
        id: UID,
        creator: address,
        recipient: address,
        exchange_for: ID,
        escrowed: Option<T>,
        expiry_date: u64,
    }

    const EWrongOwner: u64 = 0;
    const EWrongRecipient: u64 = 1;
    const EWrongExchangeObject: u64 = 2;
    const EAlreadyExchangedOrCancelled: u64 = 3;
    const EExpiredEscrow: u64 = 4;

    public fun create<T: key + store, ExchangeForT: key + store>(
        recipient: address,
        exchange_for: ID,
        escrowed_item: T,
        expiry_duration: u64,
        ctx: &mut TxContext
    ) {
        let creator = tx_context::sender(ctx);
        let id = object::new(ctx);
        let escrowed = Some(escrowed_item);
        let expiry_date = env::current_time() + expiry_duration;
        transfer::public_share_object(
            EscrowedObj<T, ExchangeForT> {
                id, creator, recipient, exchange_for, escrowed, expiry_date
            }
        );
    }

    public entry fun exchange<T: key + store, ExchangeForT: key + store>(
        obj: ExchangeForT,
        escrow: &mut EscrowedObj<T, ExchangeForT>,
        ctx: &TxContext
    ) {
        assert!(option::is_some(&escrow.escrowed), EAlreadyExchangedOrCancelled);
        assert!(&tx_context::sender(ctx) == &escrow.recipient, EWrongRecipient);
        assert!(object::borrow_id(&obj) == &escrow.exchange_for, EWrongExchangeObject);
        assert!(env::current_time() < escrow.expiry_date, EExpiredEscrow);

        let escrowed_item = option::unwrap(option::take(&mut escrow.escrowed));
        transfer::public_transfer(escrowed_item, tx_context::sender(ctx));
        transfer::public_transfer(obj, escrow.creator);
    }

    public entry fun cancel<T: key + store, ExchangeForT: key + store>(
        escrow: &mut EscrowedObj<T, ExchangeForT>,
        ctx: &TxContext
    ) {
        assert!(&tx_context::sender(ctx) == &escrow.creator, EWrongOwner);
        assert!(option::is_some(&escrow.escrowed), EAlreadyExchangedOrCancelled);
        transfer::public_transfer(option::unwrap(option::take(&mut escrow.escrowed)), escrow.creator);
    }
}