// Reference Codes: https://github.com/MystenLabs/sui/tree/main/sui_programmability/examples

// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module defi::some_amm {
    use defi::dev_pass::{Self, Subscription, SingleUse};
    use sui::tx_context::{Self, TxContext};

    struct DEVPASS has drop {}

    entry fun swap<T, S>(s: &Subscription<DEVPASS>) { /* ... */ }

    public fun dev_swap<T, S>(p: SingleUse<DEVPASS>): bool { /* ... */ true }

    public fun purchase_pass(ctx: &mut TxContext) {
        dev_pass::transfer(
            DEVPASS {},
            dev_pass::issue_subscription(DEVPASS {}, 100, ctx),
            tx_context::sender(ctx)
        )
    }

    public fun topup_pass(s: &mut Subscription<DEVPASS>) {
        dev_pass::add_uses(DEVPASS {}, s, 10)
    }
}