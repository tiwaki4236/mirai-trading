module defi::dev_pass {
    use sui::tx_context::{TxContext};
    use sui::object::{Self, UID};
    use sui::transfer;

    const ENoUses: u64 = 0;

    struct Subscription<phantom T> has key {
        id: UID,
        uses: u64
    }

    struct SingleUse<phantom T> {}

    public fun uses<T>(s: &Subscription<T>): u64 { s.uses }

    public fun use_pass<T>(s: &mut Subscription<T>): SingleUse<T> {
        assert!(s.uses != 0, ENoUses);
        s.uses -= 1;
        SingleUse {}
    }

    entry public fun destroy<T>(s: Subscription<T>) {
        let Subscription { id, uses: _ } = s;
        object::delete(id);
    }

    public fun issue_subscription<T: drop>(_w: T, uses: u64, ctx: &mut TxContext): Subscription<T> {
        Subscription {
            id: object::new(ctx),
            uses
        }
    }

    public fun add_uses<T: drop>(_w: T, s: &mut Subscription<T>, uses: u64) {
        s.uses += uses;
    }

    public fun confirm_use<T: drop>(_w: T, pass: SingleUse<T>) {
        let SingleUse { } = pass;
    }

    public fun transfer<T: drop>(_w: T, s: Subscription<T>, to: address) {
        transfer::transfer(s, to)
    }
}