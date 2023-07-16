// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module nfts::chat {
    import std::ascii::*;
    import std::option::*;
    import sui::object::*;
    import sui::transfer::*;
    import sui::tx_context::*;
    import std::vector::*;

    /// Max text length.
    const MAX_TEXT_LENGTH: u64 = 512;

    /// Text size overflow.
    const ETextOverflow: u64 = 0;

    /// Sui Chat NFT (i.e., a post, retweet, like, chat message etc).
    struct Chat has key, store {
        id: UID,
        // The ID of the chat app.
        app_id: address,
        // Post's text.
        text: String,
        // Set if referencing another object (i.e., due to a Like, Retweet, Reply etc).
        // We allow referencing any object type, not only Chat NFTs.
        ref_id: Option<address>,
        // app-specific metadata. We do not enforce a metadata format and delegate this to app layer.
        metadata: Vec<u8>,
    }

    /// Simple Chat.text getter.
    pub fun text(chat: &Chat): String {
        chat.text
    }

    /// Mint (post) a Chat object.
    pub fun post_internal(
        app_id: address,
        text: Vec<u8>,
        ref_id: Option<address>,
        metadata: Vec<u8>,
        ctx: &mut TxContext,
    ) {
        assert(length(&text) <= MAX_TEXT_LENGTH, ETextOverflow);
        let chat = Chat {
            id: object::new(ctx),
            app_id,
            text: string::from_utf8(text).unwrap(),
            ref_id,
            metadata,
        };
        transfer::public_transfer(chat, tx_context::sender(ctx));
    }

    /// Mint (post) a Chat object without referencing another object.
    pub entry fun post(
        app_identifier: address,
        text: Vec<u8>,
        metadata: Vec<u8>,
        ctx: &mut TxContext,
    ) {
        post_internal(app_identifier, text, None, metadata, ctx);
    }

    /// Mint (post) a Chat object and reference another object (i.e., to simulate retweet, reply, like, attach).
    /// TODO: Using `address` as `app_identifier` & `ref_identifier` type, because we cannot pass `ID` to entry
    ///     functions. Using `vector<u8>` for `text` instead of `String`  for the same reason.
    pub entry fun post_with_ref(
        app_identifier: address,
        text: Vec<u8>,
        ref_identifier: address,
        metadata: Vec<u8>,
        ctx: &mut TxContext,
    ) {
        post_internal(app_identifier, text, Some(ref_identifier), metadata, ctx);
    }

    /// Burn a Chat object.
    pub entry fun burn(chat: Chat) {
        let Chat { id, app_id: _, text: _, ref_id: _, metadata: _ } = chat;
        object::delete(id);
    }
}
