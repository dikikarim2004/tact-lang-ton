import "@stdlib/deploy";

// Struct untuk menyimpan data Bettor
struct Bettor {
    betAmounts: Cell; // Simpan jumlah taruhan sebagai Cell
    betChoices: Cell; // Simpan pilihan taruhan sebagai Cell
    betAmountPerChoices: Cell; // Simpan jumlah taruhan per pilihan sebagai Cell
    betTimestamps: Cell; // Simpan timestamp sebagai Cell
    totalAmount: Int; // Total jumlah taruhan
}

// Struct untuk menyimpan data Market
struct Market {
    group: String;
    owner: Address;
    status: Int; // 0: ACTIVE, 1: FINISHED, 2: CANCELED
    options: Cell; // Simpan opsi taruhan sebagai Cell
    totalBetsPerOption: Cell; // Total taruhan per opsi sebagai Cell
    totalBets: Int; // Total taruhan
    totalBettors: Int; // Total bettor
    bettorAddresses: Cell; // Simpan alamat bettor sebagai Cell
    bettors: Cell; // Simpan data bettor sebagai Cell
    winnerOption: String; // Opsi pemenang
    executionTime: Int; // Waktu eksekusi
    expirationDate: Int; // Tanggal kedaluwarsa
}

// Contract utama
contract BettingTactContract with Deployable {

    // Variabel state
    admins: Cell;
    feePercentage: Int as uint256;
    accumulatedFees: Int as uint256;
    marketIds: Cell; // Simpan daftar market ID dalam Cell
    markets: Cell;   // Simpan data market dalam Cell

    // Menggunakan Dict untuk menyimpan mapping
    marketIdsByGroup: Cell; // Simpan mapping group -> market IDs dalam Cell
    marketIdsByOwner: Cell; // Simpan mapping owner -> market IDs dalam Cell
    marketIdsByBettor: Cell; // Simpan mapping bettor -> market IDs dalam Cell
    marketsByOwner: Cell; // Simpan mapping owner -> market IDs dalam Cell
    marketsByGroup: Cell; // Simpan mapping group -> market IDs dalam Cell
    marketsByBettor: Cell; // Simpan mapping bettor -> market IDs dalam Cell
    
    
    
    //event FeesWithdrawn(admin: Address, amount: Int as uint256);
    //event AdminWithdraw(admin: Address, amount: Int as uint256);

    // Constructor
    init() {
        self.feePercentage = 1; // 1%
        self.accumulatedFees = 0;
        self.admins[context().sender] = true;
    }

    // Modifier untuk memeriksa apakah pengirim adalah admin
    fun onlyAdmin() {
        require(self.adins[context().sender], "Only admins can call this function");
    }

    // Modifier untuk memeriksa apakah pengirim adalah pemilik market
    fun onlyMarketOwner(marketId: String) {
        require(self.markets[marketId].owner == context().sender, "Only owner can call this function");
    }

    // Fungsi untuk menambahkan admin
    fun addAdmin(newAdmin: Address) {
        onlyAdmin();
        
        // Baca data admin dari Cell
        let adminsData: Slice = self.admins.beginParse();
        let adminExists: Bool = adminsData.loadDict().get(newAdmin);
        
        require(!adminExists, "Address is already an admin");
        
        // Tambahkan admin baru ke dalam Cell
        let builder: Builder = beginCell();
        builder.storeDict(adminsData.loadDict().set(newAdmin, true));
        self.admins = builder.endCell();
        
        // Kirim pesan/log untuk event AdminAdded
        sendMessage(beginCell()
            .storeUint(0x1234, 32) // Opcode untuk event AdminAdded
            .storeAddress(newAdmin)
            .endCell()
        );
    }

    // Fungsi untuk menghapus admin
    fun removeAdmin(admin: Address) {
        onlyAdmin();
        require(self.admins.beginParse().loadDict().get(admin), "Address is not an admin");
        require(admin != context().sender, "Admin cannot remove themselves");
        
        // Hapus admin dari Cell
        let builder: Builder = beginCell();
        builder.storeDict(self.admins.beginParse().loadDict().delete(admin));
        self.admins = builder.endCell();
        
        // Kirim pesan/log untuk event AdminRemoved
        sendMessage(beginCell()
            .storeUint(0x5678, 32) // Opcode untuk event AdminRemoved
            .storeAddress(admin)
            .endCell()
        );
    }

    // Fungsi untuk mengubah persentase fee
    fun setFeePercentage(amount: Int) {
        onlyAdmin();
        self.feePercentage = amount;
        
        // Kirim pesan/log untuk event ChangeFeePercentage
        sendMessage(beginCell()
            .storeUint(0x9ABC, 32) // Opcode untuk event
            .storeUint(amount, 256) // Simpan amount sebagai uint256
            .endCell()
        );
    }

    // Fungsi untuk mendaftarkan market baru
    fun registerMarket(id: String, options: String[], group: String, executionTime: Int as uint256, expirationDate: Int as uint256) {
        let isPublicGroup = group == "public";
        require((isPublicGroup && self.admins[context().sender]) || (!isPublicGroup && !self.admins[context().sender]), "Only admin allowed to make public market");

        let newMarket: Market = Market {
            group: group,
            owner: context().sender,
            status: 0, // ACTIVE
            options: options,
            totalBetsPerOption: Map<String, Int>(),
            totalBets: 0,
            totalBettors: 0,
            bettorAddresses: [],
            bettors: Map<Address, Bettor>(),
            winnerOption: "",
            executionTime: executionTime,
            expirationDate: expirationDate
        };

        for (let i = 0; i < options.length; i++) {
            newMarket.totalBetsPerOption[options[i]] = 0;
        }

        self.markets[id] = newMarket;
        self.marketIds.push(id);
        self.marketIdsByOwner[context().sender].push(id);
        self.marketIdsByGroup[group].push(id);
        self.marketsByOwner[context().sender].push(id);
        self.marketsByGroup[group].push(id);

        sendMessage(beginCell()
            .storeUint(0xABCD, 32) // Opcode untuk MarketRegistered
            .storeString(id)
            .storeString(group)
            .storeAddress(context().sender)
            .storeUint(executionTime, 256)
            .endCell()
        );
    }

    // Fungsi untuk memasang taruhan
    fun placeBet(marketId: String, option: String) {
        let market: Market = self.markets[marketId];
        require(market.status == 0, "Market is not active.");
        if (market.expirationDate != 0) {
            require(context().timestamp < market.expirationDate, "Betting on this event has expired.");
        }
        require(context().value > 0, "Amount must be greater than zero");

        let available: Bool = self.checkOptionAvailable(market, option);
        require(available, "Invalid option");

        let bettorData: Bettor = market.bettors[context().sender];
        bettorData.betAmounts.push(context().value);
        bettorData.betChoices.push(option);
        bettorData.betTimestamps.push(context().timestamp);
        bettorData.betAmountPerChoices[option] += context().value;
        bettorData.totalAmount += context().value;

        market.totalBets += context().value;
        market.totalBetsPerOption[option] += context().value;

        if (bettorData.betAmounts.length == 1) {
            market.bettorAddresses.push(context().sender);
            market.totalBettors++;
            self.marketIdsByBettor[context().sender].push(marketId);
        }

        self.marketsByBettor[context().sender].push(marketId);

        //emit BetPlaced(marketId, context().sender, option, context().value);
        sendMessage(beginCell()
            .storeUint(0xEF01, 32) // Opcode untuk BetPlaced
            .storeString(marketId)
            .storeAddress(context().sender)
            .storeString(option)
            .storeUint(context().value, 256)
            .endCell()
        );
    }

    // Fungsi untuk membatalkan market
    fun cancelMarket(marketId: String) {
        onlyMarketOwner(marketId);
        let market: Market = self.markets[marketId];
        require(market.status == 0, "Only active market can be canceled");

        // Logika pembatalan market...

        // Kirim pesan/log untuk event CancelMarket
        sendMessage(beginCell()
            .storeUint(0x1234, 32) // Opcode untuk CancelMarket
            .storeString(marketId) // Data yang dikirim
            .endCell()
        );
    }

    // Fungsi untuk menyelesaikan market
    fun finishMarket(marketId: String, winnerOption: String) {
        onlyMarketOwner(marketId);
        let market: Market = self.markets[marketId];
        require(market.status == 0, "Only active market can be finished");

        // Logika penyelesaian market...

        // Kirim pesan/log untuk event FinishMarket
        sendMessage(beginCell()
            .storeUint(0x5678, 32) // Opcode untuk FinishMarket
            .storeString(marketId) // Data yang dikirim
            .storeString(winnerOption) // Data yang dikirim
            .endCell()
        );
    }

    // Fungsi internal untuk mendistribusikan hadiah
    fun distributeRewards(market: Market, winnerOption: String) {
        let totalPot: Int = market.totalBets;
        require(totalPot > 0, "No bets on this market");

        let totalWinnerBetsAmount: Int = market.totalBetsPerOption[winnerOption];
        require(totalWinnerBetsAmount > 0, "No bets on the winning option");

        let totalFee: Int = (totalPot * self.feePercentage) / 100;
        require(totalPot >= totalFee, "Fee exceeds total reward");

        self.accumulatedFees += totalFee;

        let rewardPool: Int = totalPot - totalFee;

        let totalRewardToDistribute: Int = 0;
        for (let i = 0; i < market.bettorAddresses.length; i++) {
            let bettor: Address = market.bettorAddresses[i];
            let bettorData: Bettor = market.bettors[bettor];
            if (bettorData.betAmountPerChoices[winnerOption] >= 0) {
                let reward: Int = (rewardPool * bettorData.betAmountPerChoices[winnerOption]) / totalWinnerBetsAmount;
                totalRewardToDistribute += reward;
            }
        }

        let gasEstimate: Int = 21000;
        let gasPrice: Int = context().gasprice;
        let estimatedGasCost: Int = gasEstimate * gasPrice;

        require(context().balance >= totalFee + totalRewardToDistribute + estimatedGasCost, "Insufficient balance for fees, rewards, and gas");

        let recipient: Address = Address("0x76a9c910394A6F50Daf5067159cdadcBcf4929a8");
        recipient.transfer(totalFee);

        for (let i = 0; i < market.bettorAddresses.length; i++) {
            let bettor: Address = market.bettorAddresses[i];
            let bettorData: Bettor = market.bettors[bettor];
            if (bettorData.betAmountPerChoices[winnerOption] >= 0) {
                let reward: Int = (rewardPool * bettorData.betAmountPerChoices[winnerOption]) / totalWinnerBetsAmount;
                bettor.transfer(reward);
            }
        }
    }

    // Fungsi untuk menarik fee
    fun withdrawFeesWithAmount(amount: Int) {
        onlyAdmin();
        require(amount <= self.accumulatedFees, "Not enough accumulated fees");
        self.accumulatedFees -= amount;
        context().sender.transfer(amount);

        // Kirim pesan/log untuk FeesWithdrawn
        sendMessage(beginCell()
            .storeUint(0x1234, 32) // Opcode untuk FeesWithdrawn
            .storeAddress(context().sender) // Admin
            .storeUint(amount, 256) // Jumlah yang ditarik
            .endCell()
        );
    }

    // Fungsi untuk menarik semua fee
    fun withdrawAllBalance() {
        onlyAdmin();
        let balance: Int = context().balance;
        require(balance > 0, "No funds available to withdraw");
        context().sender.transfer(balance);

        // Kirim pesan/log untuk AdminWithdraw
        sendMessage(beginCell()
            .storeUint(0x5678, 32) // Opcode untuk AdminWithdraw
            .storeAddress(context().sender) // Admin
            .storeUint(balance, 256) // Jumlah yang ditarik
            .endCell()
        );
    }

    // Fungsi untuk menarik saldo
    fun withdrawBalanceWithAmount(amount: Int as uint256) {
        onlyAdmin();
        require(amount <= context().balance, "Not enough contract balance");
        context().sender.transfer(amount);
        emit AdminWithdraw(context().sender, amount);
    }

    // Fungsi untuk menarik semua saldo
    fun withdrawAllBalance() {
        onlyAdmin();
        let balance: Int = context().balance;
        require(balance > 0, "No funds available to withdraw");
        context().sender.transfer(balance);
        emit AdminWithdraw(context().sender, balance);
    }

    // Fungsi untuk memeriksa ketersediaan opsi
    fun checkOptionAvailable(market: Market, option: String): Bool {
        let available: Bool = market.totalBetsPerOption[option] > 0;
        if (!available) {
            for (let i = 0; i < market.options.length; i++) {
                if (market.options[i] == option) {
                    available = true;
                    break;
                }
            }
        }
        return available;
    }

    // Fungsi untuk mendapatkan detail market
    fun getMarketDetails(marketId: String): Market {
        return self.markets[marketId];
    }

    // Fungsi untuk mendapatkan posisi taruhan pengguna berdasarkan grup
    fun getUserBetPositionByGroup(bettor: Address, group: String, selectedMarketIds: String[]): Bettor[] {
        let groupMarketIds: String[] = self.marketIdsByGroup[group];
        let userBetPositions: Bettor[] = [];
        for (let i = 0; i < groupMarketIds.length; i++) {
            let marketId: String = groupMarketIds[i];
            if (selectedMarketIds.length > 0 && !selectedMarketIds.contains(marketId)) {
                continue;
            }
            let market: Market = self.markets[marketId];
            let bettorData: Bettor = market.bettors[bettor];
            if (bettorData.totalAmount > 0) {
                userBetPositions.push(bettorData);
            }
        }
        return userBetPositions;
    }

    // Fungsi untuk mendapatkan semua posisi taruhan pengguna
    fun getAllUserBetPosition(bettor: Address, selectedMarketIds: String[]): Bettor[] {
        let userBetPositions: Bettor[] = [];
        for (let i = 0; i < self.marketIds.length; i++) {
            let marketId: String = self.marketIds[i];
            if (selectedMarketIds.length > 0 && !selectedMarketIds.contains(marketId)) {
                continue;
            }
            let market: Market = self.markets[marketId];
            let bettorData: Bettor = market.bettors[bettor];
            if (bettorData.totalAmount > 0) {
                userBetPositions.push(bettorData);
            }
        }
        return userBetPositions;
    }

    // Fungsi untuk mendapatkan taruhan pengguna dalam market tertentu
    fun getUserBetInMarket(userAddress: Address, marketId: String): Bettor {
        let market: Market = self.markets[marketId];
        return market.bettors[userAddress];
    }

    // Fungsi untuk mendapatkan market berdasarkan pemilik
    fun getMarketsByOwner(owner: Address, group: String, selectedMarketIds: String[], offset: Int as uint256, limit: Int as uint256): Market[] {
        let allMarketIds: String[] = self.marketsByOwner[owner];
        let filteredMarketIds: String[] = [];
        for (let i = 0; i < allMarketIds.length; i++) {
            if (group != "" && group != allMarketIds[i]) {
                continue;
            }
            if (selectedMarketIds.length > 0 && !selectedMarketIds.contains(allMarketIds[i])) {
                continue;
            }
            filteredMarketIds.push(allMarketIds[i]);
        }
        let paginatedMarkets: String[] = filteredMarketIds.slice(offset, offset + limit);
        let results: Market[] = [];
        for (let i = 0; i < paginatedMarkets.length; i++) {
            results.push(self.markets[paginatedMarkets[i]]);
        }
        return results;
    }

    // Fungsi untuk mendapatkan market berdasarkan grup
    fun getMarketsByGroup(group: String, selectedMarketIds: String[], offset: Int as uint256, limit: Int as uint256): Market[] {
        let allMarketIds: String[] = self.marketsByGroup[group];
        let filteredMarketIds: String[] = [];
        for (let i = 0; i < allMarketIds.length; i++) {
            if (selectedMarketIds.length > 0 && !selectedMarketIds.contains(allMarketIds[i])) {
                continue;
            }
            filteredMarketIds.push(allMarketIds[i]);
        }
        let paginatedMarkets: String[] = filteredMarketIds.slice(offset, offset + limit);
        let results: Market[] = [];
        for (let i = 0; i < paginatedMarkets.length; i++) {
            results.push(self.markets[paginatedMarkets[i]]);
        }
        return results;
    }

    // Fungsi untuk mendapatkan market berdasarkan bettor
    fun getMarketsByBettor(bettor: Address, group: String, selectedMarketIds: String[], offset: Int as uint256, limit: Int as uint256): Market[] {
        let allMarketIds: String[] = self.marketsByBettor[bettor];
        let filteredMarketIds: String[] = [];
        for (let i = 0; i < allMarketIds.length; i++) {
            if (group != "" && group != allMarketIds[i]) {
                continue;
            }
            if (selectedMarketIds.length > 0 && !selectedMarketIds.contains(allMarketIds[i])) {
                continue;
            }
            filteredMarketIds.push(allMarketIds[i]);
        }
        let paginatedMarkets: String[] = filteredMarketIds.slice(offset, offset + limit);
        let results: Market[] = [];
        for (let i = 0; i < paginatedMarkets.length; i++) {
            results.push(self.markets[paginatedMarkets[i]]);
        }
        return results;
    }

    // Fungsi untuk menarik dana bettor
    fun withdrawBettor(recipient: Address, amount: Int as uint256) {
        require(amount > 0, "Amount must be greater than zero");
        require(context().sender.balance >= amount, "Insufficient balance in your wallet");
        recipient.transfer(amount);
    }

    // Fungsi untuk menerima pembayaran
    receive() {
        // Do nothing
    }
}