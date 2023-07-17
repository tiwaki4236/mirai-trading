// Refrence codes: : https://github.com/MystenLabs/sui/blob/main/sui_programmability/examples/nfts/sources/auction_lib.move

// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// This is a helper module for implementing two versions of an
/// English auction (https://en.wikipedia.org/wiki/English_auction),
/// one using single-owner objects only and the other using shared
/// objects.
module nfts::auction_lib {
    use std::option::{Self, Option};

    use sui::coin;
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self,TxContext};

    friend nfts::auction;
    friend nfts::shared_auction;

    /// Stores information about an auction bid.
    struct BidData has store{
        /// Coin representing the current (highest) bid.
        funds: Balance<SUI>,
        /// Address of the highest bidder.
        highest_bidder: Address,
    }

    /// Maintains the state of the auction owned by a trusted
    /// auctioneer.
    struct Auction<T: Key + Store> has key {
        id: UID,
        /// Item to be sold. It only really needs to be wrapped in
        /// Option if Auction represents a shared object but we do it
        /// for single-owner Auctions for better code re-use.
        to_sell: Option<T>,
        /// Owner of the time to be sold.
        owner: Address,
        /// Data representing the highest bid (starts with no bid)
        bid_data: Option<BidData>,
    }

    pub(friend) fun auction_owner<T: Key + Store>(auction: &Auction<T>): Address {
        auction.owner
    }

    /// Creates an auction. This is executed by the owner of the asset to be
    /// auctioned.
    pub(friend) fun create_auction<T: Key + Store>(
        to_sell: T, ctx: &mut TxContext
    ): Auction<T> {
        // A question one might asked is how do we know that to_sell
        // is owned by the caller of this entry function and the
        // answer is that it's checked by the runtime.
        Auction<T> {
            id: object::new(ctx),
            to_sell: Some(to_sell),
            owner: tx_context::sender(ctx),
            bid_data: None,
        }
    }

    /// Updates the auction based on the information in the bid
    /// (update auction if higher bid received and send coin back for
    /// bids that are too low).
    pub fun update_auction<T: Key + Store>(
        auction: &mut Auction<T>,
        bidder: Address,
        funds: Balance<SUI>,
        ctx: &mut TxContext,
    ) {
        if (option::is_none(&auction.bid_data)) {
            // first bid
            let bid_data = BidData {
                funds,
                highest_bidder: bidder,
            };
            option::set(&mut auction.bid_data, bid_data);
        } else {
            let prev_bid_data = option::get(&auction.bid_data);
            if (balance::value(&funds) > balance::value(&prev_bid_data.funds)) {
                // a bid higher than currently highest bid received
                let new_bid_data = BidData {
                    funds,
                    highest_bidder: bidder,
                };

                // update auction to reflect highest bid
                let BidData {
                    funds,
                    highest_bidder,
                } = option::replace(&mut auction.bid_data, new_bid_data);

                // transfer previously highest bid to its bidder
                send_balance(funds, highest_bidder, ctx);
            } else {
                // a bid is too low - return funds to the bidder
                send_balance(funds, bidder, ctx);
            }
        }
    }

    /// Ends the auction - transfers item to the currently highest
    /// bidder or to the original owner if no bids have been placed.
    fun end_auction<T: Key + Store>(
        to_sell: &mut Option<T>,
        owner: Address,
        bid_data: &mut Option<BidData>,
        ctx: &mut TxContext
    ) {
        let item = option::take(to_sell);
        if (option::is_some(bid_data)) {
            // bids have been placed - send funds to the original item
            // owner and the item to the highest bidder
            let BidData {
                funds,
                highest_bidder,
            } = option::take(bid_data);

            send_balance(funds, owner, ctx);
            public_transfer(item, highest_bidder);
        } else {
            // no bids placed - send the item back to the original owner
            public_transfer(item, owner);
        }
    }

    /// Ends auction and destroys auction object (can only be used if
    /// Auction is single-owner object) - transfers item to the
    /// currently highest bidder or to the original owner if no bids
    /// have been placed.
    pub fun end_and_destroy_auction<T: Key + Store>(
        auction: Auction<T>, ctx: &mut TxContext
    ) {
        let Auction { id, to_sell, owner, bid_data } = auction;
        object::delete(id);

        end_auction(&mut to_sell, owner, &mut bid_data, ctx);

        option::destroy_none(bid_data);
        option::destroy_none(to_sell);
    }

    /// Ends auction (should only be used if Auction is a shared
    /// object) - transfers item to the currently highest bidder or to
    /// the original owner if no bids have been placed.
    pub fun end_shared_auction<T: Key + Store>(
        auction: &mut Auction<T>, ctx: &mut TxContext
    ) {
        end_auction(&mut auction.to_sell, auction.owner, &mut auction.bid_data, ctx);
    }

    /// Helper for the most common operation - wrapping a balance and sending it
    fun send_balance(balance: Balance<SUI>, to: Address, ctx: &mut TxContext) {
        public_transfer(coin::from_balance(balance, ctx), to);
    }

    /// exposes transfer::transfer
    pub fun transfer<T: Key + Store>(obj: Auction<T>, recipient: Address) {
        public_transfer(obj, recipient);
    }

    pub fun share_object<T: Key + Store>(obj: Auction<T>) {
        share_object(obj);
    }
}
