// Reference Codes: https://github.com/MystenLabs/sui/tree/main/sui_programmability/examples

module defi::smart_swapper {
    use defi::some_amm::{Self, DEVPASS};
    use defi::dev_pass::{Self, Subscription};

    struct ETH {}
    struct BTC {}
    struct KTS {}

    entry fun cross_pool_swap(s: &mut Subscription<DEVPASS>) {
        let _a = some_amm::dev_swap<ETH, BTC>(dev_pass::use_pass(s));
        let _b = some_amm::dev_swap<BTC, KTS>(dev_pass::use_pass(s));
    }
}