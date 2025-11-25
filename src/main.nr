use dep::aztec::macros::aztec;

#[aztec]
contract ZStablecoin {
    use dep::aztec::prelude::{
        AztecAddress, Map, PrivateSet, PublicMutable, SharedMutable, 
        NoteHeader, NoteInterface, FunctionSelector
    };
    use dep::aztec::keys::getters::get_public_keys;
    // Importamos la definición estándar de Token
    use dep::token::Token; 

    // --- Estructuras Personalizadas (Notas) ---
    
    #[note]
    struct CDPNote {
        owner: AztecAddress,
        collateral_amount: Field,      // Cantidad de ZEC depositado
        debt_principal: Field,         // Deuda original solicitada
        start_interest_index: Field,   // Índice global al momento de abrir la posición
        header: NoteHeader,
    }

    #[storage]
    struct Storage {
        // Direcciones de los contratos vinculados
        zec_token: PublicMutable<AztecAddress>,   // El colateral (Mock ZEC)
        zusd_token: PublicMutable<AztecAddress>,  // La stablecoin que este contrato controla
        oracle: PublicMutable<AztecAddress>,      // Fuente de precios
        
        // Mapeo: Dueño -> Set de Notas de Posición
        positions: Map<AztecAddress, PrivateSet<CDPNote>>,
        
        // Variables de Riesgo y Estado Global
        min_collateral_ratio: PublicMutable<Field>, // Ej: 150 (representando 150%)
        interest_index: PublicMutable<Field>,       // Acumulador de intereses (Base 1e9)
    }

    // --- Lógica Principal ---

    #[public]
    #[initializer]
    fn constructor(
        zec_address: AztecAddress, 
        zusd_address: AztecAddress,
        oracle_address: AztecAddress
    ) {
        storage.zec_token.write(zec_address);
        storage.zusd_token.write(zusd_address);
        storage.oracle.write(oracle_address);
        
        storage.min_collateral_ratio.write(150); // 150%
        storage.interest_index.write(1000000000); // 1.0 con 9 decimales de precisión
    }

    // 1. ABRIR POSICIÓN (Privado)
    // Deposita ZEC, verifica solvencia y acuña ZUSD
    #[private]
    fn open_position(
        collateral_amount: Field, 
        borrow_amount: Field,
        oracle_price: Field // En prod: pasaría una prueba de lectura histórica
    ) {
        let user = context.msg_sender();
        let this_address = context.this_address();
        
        // A. Obtener datos globales necesarios (Lectura de estado público en privado)
        // Nota: En una app real, usaríamos un oráculo con pruebas de inclusión histórica
        let interest_index = storage.interest_index.read();
        
        // B. Gestión de Riesgo (Risk Management)
        // Valor Colateral = Cantidad * Precio
        let collateral_value = collateral_amount * oracle_price;
        // Colateral Requerido = Préstamo * Ratio (150%)
        let required_collateral = borrow_amount * storage.min_collateral_ratio.read() / 100;

        assert(collateral_value >= required_collateral, "ZStablecoin: Subcollateralized position");

        // C. Transferir Colateral (ZEC) del Usuario al Vault
        // Requiere que el usuario haya aprobado (authwit) al contrato
        let zec = storage.zec_token.read();
        Token::at(zec).transfer(user, this_address, collateral_amount).call(&mut context);

        // D. Acuñar Stablecoin (ZUSD) para el Usuario
        // El contrato ZStablecoin debe tener rol de MINTER en el contrato ZUSD
        let zusd = storage.zusd_token.read();
        Token::at(zusd).mint_private(user, borrow_amount).call(&mut context);

        // E. Crear la Nota de Posición (CDP)
        // Guardamos el índice actual para calcular intereses después
        let mut note = CDPNote {
            owner: user,
            collateral_amount: collateral_amount,
            debt_principal: borrow_amount,
            start_interest_index: interest_index,
            header: NoteHeader::empty(),
        };
        storage.positions.at(user).insert(&mut note, true);
    }

    // 2. CERRAR POSICIÓN (Privado)
    // Paga la deuda + intereses y recupera el colateral
    #[private]
    fn close_position(
        amount_to_repay: Field // Cantidad de deuda base que se quiere pagar
    ) {
        let user = context.msg_sender();
        let this_address = context.this_address();

        // A. Obtener notas de posición del usuario
        // Nota: En Noir real, iteramos sobre las notas. Aquí simplificamos asumiendo 
        // que tomamos una nota específica o usamos 'get_notes' con un filtro.
        let positions = storage.positions.at(user);
        
        // --- INICIO SIMULACIÓN DE SELECCIÓN DE NOTA ---
        // En código real: let note = positions.get_note(...);
        // Aquí asumimos que operamos sobre la última nota insertada para el ejemplo
        // y que 'amount_to_repay' coincide con el principal de esa nota.
        // --- FIN SIMULACIÓN ---

        // B. Calcular Deuda Total con Interés Compuesto
        // Formula: DeudaActual = Principal * (IndiceActual / IndiceInicial)
        let current_index = storage.interest_index.read();
        // Simulamos valores de la nota recuperada:
        let note_principal = amount_to_repay; 
        let note_start_index = 1000000000; // Valor simulado de la nota
        let note_collateral = 1000;       // Valor simulado de la nota

        // Calculamos cuánto ZUSD debe pagar realmente el usuario
        // Ejemplo: Si el índice subió de 1.0 a 1.1, paga 10% más.
        let repayment_amount = note_principal * current_index / note_start_index;

        // C. Quemar ZUSD del usuario (Repago)
        // Transfiere ZUSD del usuario al contrato y luego lo quema (o burn directo)
        let zusd = storage.zusd_token.read();
        Token::at(zusd).burn_private(user, repayment_amount).call(&mut context);

        // D. Devolver Colateral (ZEC)
        let zec = storage.zec_token.read();
        Token::at(zec).transfer(this_address, user, note_collateral).call(&mut context);

        // E. Eliminar la nota de posición (Nullify)
        positions.remove(note); 
    }

    // 3. GENERAR RENDIMIENTO (Público)
    // Incrementa el índice global. Esto hace que todas las deudas crezcan automáticamente.
    // Simula el costo de pedir prestado (borrow fee).
    #[public]
    fn accrue_interest(rate_permille: Field) {
        let current_index = storage.interest_index.read();
        // Incrementa el índice. Ej: 1000 -> 1005 (+0.5%)
        let new_index = current_index + (current_index * rate_permille / 1000);
        storage.interest_index.write(new_index);
    }
    
    // 4. LIQUIDACIÓN (Semi-Privada / Pública)
    // En un sistema ZK completo, la liquidación es compleja. 
    // Aquí proveemos un método helper para verificar solvencia públicamente si se revelan los datos.
    #[public]
    fn check_solvency(debt: Field, collateral: Field, price: Field) -> bool {
        let collateral_value = collateral * price;
        let required = debt * 150 / 100;
        collateral_value >= required
    }
}