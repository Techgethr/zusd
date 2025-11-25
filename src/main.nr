use dep::aztec::macros::aztec;

#[aztec]
contract ZStablecoin {
    use dep::aztec::prelude::{
        AztecAddress, Map, PrivateSet, PublicMutable, 
        NoteHeader, NoteInterface
    };
    use dep::aztec::keys::getters::get_public_keys;

    use dep::token::Token; 

    
    // Private NOTE to track user's collateralized debt position (CDP)
    #[note]
    struct CDPNote {
        owner: AztecAddress,
        collateral_amount: Field,      // Cantidad de ZEC depositado
        debt_principal: Field,         // Deuda original solicitada (ZUSD)
        start_interest_index: Field,   // Índice global al momento de abrir la posición
        header: NoteHeader,
    }

    #[storage]
    struct Storage {
        // Direcciones de los contratos vinculados
        admin: PublicMutable<AztecAddress>,       // Administrador para tareas críticas
        zec_token: PublicMutable<AztecAddress>,   // El colateral (Mock ZEC)
        zusd_token: PublicMutable<AztecAddress>,  // La stablecoin que este contrato controla
        oracle: PublicMutable<AztecAddress>,      // Fuente de precios
        
        // Mapeo: Dueño -> Set de Notas de Posición (CDPs)
        positions: Map<AztecAddress, PrivateSet<CDPNote>>,
        
        // Variables de Riesgo y Estado Global
        min_collateral_ratio: PublicMutable<Field>, // Ej: 150 (representando 150%)
        interest_index: PublicMutable<Field>,       // Acumulador de intereses (Base 1e9, ej: 1000000000)
    }


    #[public]
    #[initializer]
    fn constructor(
        admin_address: AztecAddress,
        zec_address: AztecAddress, 
        oracle_address: AztecAddress
    ) {
        // We initialize the admin and known addresses
        storage.admin.write(admin_address);
        storage.zec_token.write(zec_address);
        storage.oracle.write(oracle_address);
        
        // The ZUSD address is initialized later (see set_zusd_token_address)
        storage.min_collateral_ratio.write(150); 
        storage.interest_index.write(1000000000); 
    }

    // Set the ZUSD token contract address
    #[public]
    fn set_zusd_token_address(new_zusd_address: AztecAddress) {
        let admin = storage.admin.read();
        assert(context.msg_sender() == admin, "Vault: Solo el administrador puede configurar ZUSD");
        storage.zusd_token.write(new_zusd_address);
    }

    // 1. Open position (Private)
    // Deposit ZEC collateral and borrow ZUSD
    #[private]
    fn open_position(
        collateral_amount: Field, 
        borrow_amount: Field
    ) {
        let user = context.msg_sender();
        let this_address = context.this_address();
        
        let interest_index = storage.interest_index.read();
        let min_ratio = storage.min_collateral_ratio.read();

        let oracle_address = storage.oracle.read();
        
        // NOTE: In a real implementation, the selector should be obtained from the SimpleOracle contract. 
        // We use a placeholder value for demonstration.
        let get_price_selector: Field = 0x12345678; 
        
        let oracle_price_result = context.call_public_function(
            oracle_address, 
            get_price_selector, 
            &[] // No arguments
        );

        // We extract the first (and only) value (the price)
        let oracle_price = oracle_price_result.get(0);
        
        
        let collateral_value = collateral_amount * oracle_price;
        
        let required_collateral = borrow_amount * min_ratio / 100;

        assert(collateral_value >= required_collateral, "ZStablecoin: Subcollateralized position");

        
        let zec = storage.zec_token.read();
        
        Token::at(zec).transfer(user, this_address, collateral_amount).call(&mut context);

        // Mint the borrowed ZUSD to the user
        let zusd = storage.zusd_token.read();
        // Send using mint_private function in ZUSD contract
        Token::at(zusd).mint_private(user, borrow_amount).call(&mut context);

        // Create and store the CDP note
        let mut note = CDPNote {
            owner: user,
            collateral_amount: collateral_amount,
            debt_principal: borrow_amount,
            start_interest_index: interest_index,
            header: NoteHeader::empty(),
        };
        storage.positions.at(user).insert(&mut note, true);
    }

    // 2. Close the position (Private)
    // Repay ZUSD and withdraw ZEC collateral
    #[private]
    #[private]
    fn close_position(
        collateral_amount: Field,      
        debt_principal: Field,         
        start_interest_index: Field    
    ) {
        let user = context.msg_sender();
        let this_address = context.this_address();

        // We calculate the repayment amount
        let current_index = storage.interest_index.read();
        let repayment_amount = debt_principal * current_index / start_interest_index;

        // We burn the ZUSD from the user
        let zusd = storage.zusd_token.read();
        Token::at(zusd).burn_private(user, repayment_amount).call(&mut context);

        // We transfer the collateral back to the user
        let zec = storage.zec_token.read();
        Token::at(zec).transfer(this_address, user, collateral_amount).call(&mut context);

    }

    // 3. Generate yield (Public)
    // Simulate interest accrual by updating the global interest index
    #[public]
    fn accrue_interest(rate_permille: Field) {
        let admin = storage.admin.read();
        assert(context.msg_sender() == admin, "Vault: Only admin can accrue interest");

        let current_index = storage.interest_index.read();
        let new_index = current_index + (current_index * rate_permille / 1000);
        storage.interest_index.write(new_index);
    }
    
    // Solvency check, to use as help for liquidators
    #[public]
    fn check_solvency(debt: Field, collateral: Field, price: Field) -> bool {
        let min_ratio = storage.min_collateral_ratio.read();
        let collateral_value = collateral * price;
        let required = debt * min_ratio / 100;
        collateral_value >= required
    }
}