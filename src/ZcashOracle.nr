use dep::aztec::macros::aztec;

#[aztec]
// Simple Oracle Contract for Price Feeds (not for production use)
contract SimpleOracle {
    use dep::aztec::prelude::{AztecAddress, PublicMutable};

    #[storage]
    struct Storage {
        // Pricing with decimals (e.g., 300.50 USD = 30050)
        current_price: PublicMutable<Field>,
        admin: PublicMutable<AztecAddress>,
    }

    #[public]
    #[initializer]
    fn constructor(admin: AztecAddress, initial_price: Field) {
        storage.admin.write(admin);
        storage.current_price.write(initial_price);
    }

    // Update price (Admin only)
    #[public]
    fn update_price(new_price: Field) {
        let admin = storage.admin.read();
        assert(context.msg_sender() == admin, "Oracle: Not authorized");
        storage.current_price.write(new_price);
    }

    // Read price (public)
    #[public]
    fn get_price() -> Field {
        storage.current_price.read()
    }
}