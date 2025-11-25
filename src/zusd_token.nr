use dep::aztec::macros::aztec;
use dep::aztec::prelude::{AztecAddress, PublicMutable, Map, PrivateSet, ValueNote};


#[aztec]
contract ZUSDToken {
    use dep::aztec::prelude::{AztecAddress, Map, PrivateSet, ValueNote};

    #[storage]
    struct Storage {
        //  ZStablecoin Engine
        vault_address: PublicMutable<AztecAddress>,
        // Private Note Balances (ZUSD)
        balances: Map<AztecAddress, PrivateSet<ValueNote>>,
        // ZUSD Total Supply (public for auditing)
        total_supply: PublicMutable<Field>,
    }

    #[public]
    #[initializer]
    fn constructor(vault: AztecAddress) {
        // ZStablecoin Vault authorized to mint/burn ZUSD
        storage.vault_address.write(vault);
        storage.total_supply.write(0);
    }

    // 1. Private Mint
    // Only from the ZStablecoin Vault Contract
    #[private]
    fn mint_private(to: AztecAddress, amount: Field) {
        let vault = storage.vault_address.read();
        
        assert(context.msg_sender() == vault, "ZUSD: Only the Vault can mint");
        
        // 1. We create a new ValueNote for the 'to' address
        let mut note = ValueNote::new(amount, to);
        
        // 2.We insert the note in the private set of 'to'
        storage.balances.at(to).insert(&mut note, true);
        
        // 3. We update the total supply (Public)
        storage.total_supply.write(storage.total_supply.read() + amount);
    }

    // 2. Private Transfer
    // Allow users to send ZUSD privately
    #[private]
    fn transfer_private(to: AztecAddress, amount: Field) {
        let sender = context.msg_sender();
        
        // A. We burn notes from the sender and create a change note if needed
        storage.balances.at(sender).sub(amount, sender);

        // B. Create and insert a new note for the recipient
        let mut note = ValueNote::new(amount, to);
        storage.balances.at(to).insert(&mut note, true);
    }

    // 3. Private burn
    #[private]
    fn burn_private(from: AztecAddress, amount: Field) {
        let vault = storage.vault_address.read();
        // Just the owner of tokens or the vault can burn tokens
        assert(context.msg_sender() == from || context.msg_sender() == vault, "ZUSD: Unauthorized burn");
        
        // A. We burn notes from the 'from' address
        storage.balances.at(from).sub(amount, from);

        // B. We update the total supply (Public)
        storage.total_supply.write(storage.total_supply.read() - amount);
    }

    // 4. Get the private balance of an address
    #[view]
    fn balance_of_private(owner: AztecAddress) -> Field {
        storage.balances.at(owner).compute_private_note_sum()
    }
}