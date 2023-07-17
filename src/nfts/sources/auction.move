// Refrence codes: https://github.com/MystenLabs/sui/blob/main/sui_programmability/examples/nfts/sources/auction.move

// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

///  This module is an implementation of an English auction
///  (https://en.wikipedia.org/wiki/English_auction) using single-owner
///  objects only. There are three types of parties participating in an
///  auction:
///  - auctioneer - a trusted party that runs the auction
///  - owner - the original owner of an item that is sold at an
///    auction; the owner submits a request to an auctioneer which runs
///    the auction
///  - bidders - parties interested in purchasing items sold
///    at an auction; they submit bids to an auctioneer to affect the
///    state of an auction
///
///  A typical lifetime of an auction looks as follows:
///  - The auction starts with the owner sending an item to be sold along with
///    its own address to the auctioneer who creates and initializes an
///    auction.
///  - Bidders send their bid to the auctioneer.
///    A bid consists of the funds offered for the item and the bidder's address.
///  - The auctioneer periodically inspects the bids:
///    - (inspected bid > current best bid (initially there is no bid)):
///      The auctioneer updates the auction with the current bid
///      and the funds of the previous highest bid are sent back to their owner.
///    - (inspected bid <= current best bid):
///      The auctioneer sents the inspected bid's funds back to the new bidder,
///      and the auction remains unchanged.
///  - The auctioneer eventually ends the auction:
///    - if no bids were received, the item goes back to the original owner
///    - otherwise the funds accumulated in the auction go to the
///      original owner and the item goes to the bidder that won the auction
module nfts::auction {
    use sui::coin::Coin;
    use sui::balance::Balance;
    use sui::sui::SUI;
    use sui::object::{ID, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;

    use nfts::auction_lib::Auction;

    // Error codes.
    const EWrongAuction: u64 = 1;

    struct Bid has key{
        id: UID,
        bidder: Address,
        auction_id: ID,
        bid: Balance<SUI>,
    }

    pub fun create_auction<T: Key + Store>(
        to_sell: T, auctioneer: Address, ctx: &mut TxContext
    ): ID {
        let auction = Auction<T>::create_auction(to_sell, ctx);
        let id = object::id(&auction);
        auction.transfer(auctioneer);
        id
    }

    pub fun bid(
        coin: Coin<SUI>, auction_id: ID, auctioneer: Address, ctx: &mut TxContext
    ) {
        let bid = Bid {
            id: object::new(ctx),
            bidder: tx_context::sender(ctx),
            auction_id,
            bid: Balance<SUI>::from(coin),
        };

        transfer(bid, auctioneer);
    }

    pub entry fun update_auction<T: Key + Store>(
        auction: &mut Auction<T>, bid: Bid, ctx: &mut TxContext
    ) {
        let Bid { id, bidder, auction_id, bid: balance } = bid;
        assert(object::borrow_id(auction) == &auction_id, EWrongAuction);
        auction.update_auction(bidder, balance, ctx);

        object::delete(id);
    }

    pub fun end_auction<T: Key + Store>(
        auction: Auction<T>, ctx: &mut TxContext
    ) {
        auction.end_and_destroy_auction(ctx);
    }
}
