// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

contract DeFiBank {
    struct Account {
        uint256 balance;
        bool isSavingsAccount;
        bool isAccountActive;
        uint256 withdrawCount;
        uint256 lastWithdrawTime;
        uint256 reserveFund;
        uint256 interestRate;
        uint256 serviceCharge;
        uint256 maxWithdrawalAmount;
        bytes32 hashedPIN;
        bool isLoanActive;
        Loan loan;
    }

    struct Loan {
        bool isLoanTaken;
        bool isLoanRepaid;
        uint256 principalAmount;
        uint256 loanInterestRate;
        uint256 collateralAmount;
        uint256 loanRepaymentAmount;
        uint256 loanDueTime;
    }

    mapping(address => Account) private accounts;
    address private owner;

    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);
    event Transfer(
        address indexed sender,
        address indexed recipient,
        uint256 amount
    );
    event LoanTaken(
        address indexed account,
        uint256 loanAmount,
        uint256 collateralAmount
    );
    event LoanRepaid(
        address indexed account,
        uint256 loanAmount,
        uint256 interestAmount
    );
    event LoanDefaulted(address indexed account, uint256 collateralAmount);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can call this function."
        );
        _;
    }

    modifier onlyActiveAccount(address _account) {
        require(accounts[_account].isAccountActive, "Account is inactive.");
        _;
    }

    modifier onlyValidPIN(address _account, uint256 _pin) {
        require(validatePIN(_account, _pin), "Incorrect PIN.");
        _;
    }

    function createAccount(uint256 _pin, bool _isSavingsAccount) external {
        require(accounts[msg.sender].balance == 0, "Account already exists.");
        require(
            _isSavingsAccount != accounts[msg.sender].isSavingsAccount,
            "Cannot have both savings and current account."
        );

        bytes32 hashedPIN = hashPIN(_pin);
        accounts[msg.sender] = Account({
            balance: 0,
            isSavingsAccount: _isSavingsAccount,
            isAccountActive: true,
            withdrawCount: 0,
            lastWithdrawTime: 0,
            reserveFund: _isSavingsAccount ? 5000 : 1000,
            interestRate: _isSavingsAccount ? 65 / uint256(10) : 0,
            serviceCharge: 0,
            maxWithdrawalAmount: _isSavingsAccount ? 20000 : 0,
            hashedPIN: hashedPIN,
            isLoanActive: false,
            loan: Loan({
                isLoanTaken: false,
                isLoanRepaid: false,
                principalAmount: 0,
                loanInterestRate: 0,
                collateralAmount: 0,
                loanRepaymentAmount: 0,
                loanDueTime: 0
            })
        });
    }

    function deposit() external payable onlyActiveAccount(msg.sender) {
        accounts[msg.sender].balance += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount, uint256 _pin)
        external
        onlyActiveAccount(msg.sender)
        onlyValidPIN(msg.sender, _pin)
    {
        Account storage account = accounts[msg.sender];
        uint256 currentWithdrawalTime = block.timestamp;

        require(_amount <= account.balance, "Insufficient balance");
        require(
            canWithdraw(account, currentWithdrawalTime),
            "Exceeded maximum withdrawal limit"
        );

        if (account.isSavingsAccount) {
            account.serviceCharge = getServiceCharge(
                account,
                currentWithdrawalTime
            );

            require(
                account.balance - _amount - account.serviceCharge >=
                    account.reserveFund,
                "Insufficient reserve fund"
            );
        } else {
            require(
                _amount <= account.balance - account.reserveFund,
                "Insufficient balance"
            );
            account.serviceCharge = 0;
        }

        account.balance -= (_amount + account.serviceCharge);
        account.lastWithdrawTime = currentWithdrawalTime;
        account.withdrawCount += 1;

        payable(msg.sender).transfer(_amount);
        emit Withdraw(msg.sender, _amount);
    }

    function transfer(
        address _recipient,
        uint256 _amount,
        uint256 _pin
    )
        external
        onlyActiveAccount(msg.sender)
        onlyValidPIN(msg.sender, _pin)
        onlyActiveAccount(_recipient)
    {
        Account storage senderAccount = accounts[msg.sender];
        require(_amount <= senderAccount.balance, "Insufficient balance");

        Account storage recipientAccount = accounts[_recipient];

        senderAccount.balance -= _amount;
        recipientAccount.balance += _amount;

        payable(_recipient).transfer(_amount); // Transfer Ether to the recipient's account

        emit Transfer(msg.sender, _recipient, _amount);
    }

    function takeLoan(
        uint256 _loanAmount,
        uint256 _collateralAmount,
        uint256 _loanType,
        uint256 _pin
    ) external onlyActiveAccount(msg.sender) onlyValidPIN(msg.sender, _pin) {
        Account storage account = accounts[msg.sender];
        require(!account.isLoanActive, "Loan is already active");

        require(_loanType >= 1 && _loanType <= 5, "Invalid loan type");

        uint256 loanInterestRate = getLoanInterestRate(_loanType);
        uint256 loanRepaymentAmount = calculateLoanRepaymentAmount(
            _loanAmount,
            loanInterestRate
        );

        require(
            _collateralAmount >= loanRepaymentAmount,
            "Insufficient collateral"
        );

        Loan memory loan = Loan({
            isLoanTaken: true,
            isLoanRepaid: false,
            principalAmount: _loanAmount,
            loanInterestRate: loanInterestRate,
            collateralAmount: _collateralAmount,
            loanRepaymentAmount: loanRepaymentAmount,
            loanDueTime: block.timestamp + 30 days
        });

        account.isLoanActive = true;
        account.loan = loan;

        emit LoanTaken(msg.sender, _loanAmount, _collateralAmount);
    }

    function repayLoan(uint256 _pin)
        external
        payable
        onlyActiveAccount(msg.sender)
        onlyValidPIN(msg.sender, _pin)
    {
        Account storage account = accounts[msg.sender];
        require(account.isLoanActive, "No active loan");

        Loan storage loan = account.loan;
        require(!loan.isLoanRepaid, "Loan is already repaid");

        require(
            msg.value >= loan.loanRepaymentAmount,
            "Insufficient repayment amount"
        );

        uint256 interestAmount = loan.loanRepaymentAmount -
            loan.principalAmount;
        uint256 remainingAmount = msg.value - loan.loanRepaymentAmount;

        account.balance += remainingAmount;
        account.isLoanActive = false;
        loan.isLoanRepaid = true;

        emit LoanRepaid(msg.sender, loan.principalAmount, interestAmount);
    }

    function checkLoanStatus(address _account, uint256 _pin)
        external
        view
        onlyActiveAccount(_account)
        onlyValidPIN(_account, _pin)
        returns (
            bool isLoanActive,
            bool isLoanRepaid,
            uint256 principalAmount,
            uint256 loanInterestRate,
            uint256 loanDueTime,
            uint256 loanRepaymentAmount,
            uint256 collateralAmount,
            string memory loanType
        )
    {
        Account storage account = accounts[_account];
        Loan storage loan = account.loan;

        isLoanActive = account.isLoanActive;
        isLoanRepaid = loan.isLoanRepaid;
        principalAmount = loan.principalAmount;
        loanInterestRate = loan.loanInterestRate;
        loanDueTime = loan.loanDueTime;
        loanRepaymentAmount = loan.loanRepaymentAmount;
        collateralAmount = loan.collateralAmount;

        loanType = getLoanTypeDescription(loan.loanInterestRate);

        return (
            isLoanActive,
            isLoanRepaid,
            principalAmount,
            loanInterestRate,
            loanDueTime,
            loanRepaymentAmount,
            collateralAmount,
            loanType
        );
    }

    function defaultLoan(address _account, uint256 _pin)
        external
        onlyActiveAccount(_account)
        onlyValidPIN(_account, _pin)
    {
        Account storage account = accounts[_account];
        Loan storage loan = account.loan;

        require(account.isLoanActive, "No active loan");
        require(!loan.isLoanRepaid, "Loan is already repaid");
        require(block.timestamp >= loan.loanDueTime, "Loan not yet due");

        uint256 collateralAmount = loan.collateralAmount;
        account.isLoanActive = false;
        loan.isLoanRepaid = true;
        account.isAccountActive = false;
        account.balance = 0;

        // Liquidate collateral (Example: Transfer to contract owner)
        payable(owner).transfer(collateralAmount);

        emit LoanDefaulted(_account, collateralAmount);
    }

    function getBalance(address _account)
        external
        view
        onlyActiveAccount(_account)
        returns (
            string memory,
            bool,
            uint256,
            uint256
        )
    {
        Account storage account = accounts[_account];
        Loan storage loan = account.loan;

        bool isLoanActive = loan.isLoanTaken && !loan.isLoanRepaid;
        uint256 totalBalance = account.balance +
            (isLoanActive ? loan.principalAmount : 0);

        return (
            "Account Balance",
            isLoanActive,
            isLoanActive ? loan.principalAmount : 0,
            totalBalance
        );
    }

    function getAccountDetails(address _account, uint256 _pin)
        external
        view
        onlyValidPIN(_account, _pin)
        returns (
            string memory savingsAccount,
            string memory accountActive,
            uint256 reserveFund,
            uint256 interestRate,
            uint256 serviceCharge
        )
    {
        Account storage account = accounts[_account];

        savingsAccount = account.isSavingsAccount
            ? "Savings Account: Yes"
            : "Savings Account: No";
        accountActive = account.isAccountActive
            ? "Account Active: Yes"
            : "Account Active: No";

        return (
            savingsAccount,
            accountActive,
            account.reserveFund,
            account.interestRate,
            account.serviceCharge
        );
    }

    function setPIN(uint256 _newPIN, uint256 _pin)
        external
        onlyActiveAccount(msg.sender)
        onlyValidPIN(msg.sender, _pin)
    {
        bytes32 hashedPIN = hashPIN(_newPIN);
        accounts[msg.sender].hashedPIN = hashedPIN;
    }

    function closeAccount(uint256 _pin)
        external
        onlyActiveAccount(msg.sender)
        onlyValidPIN(msg.sender, _pin)
    {
        Account storage account = accounts[msg.sender];
        account.isAccountActive = false;
        payable(msg.sender).transfer(account.balance);
        account.balance = 0;
    }

    function getContractBalance() external view onlyOwner returns (uint256) {
        return address(this).balance;
    }

    function validatePIN(address _account, uint256 _pin)
        internal
        view
        returns (bool)
    {
        return hashPIN(_pin) == accounts[_account].hashedPIN;
    }

    function hashPIN(uint256 _pin) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_pin));
    }

    function canWithdraw(
        Account storage _account,
        uint256 _currentWithdrawalTime
    ) internal view returns (bool) {
        if (!_account.isSavingsAccount) {
            return true;
        }

        if (_account.withdrawCount < 3) {
            return true;
        }

        uint256 timeDifference = _currentWithdrawalTime -
            _account.lastWithdrawTime;
        if (
            _account.withdrawCount >= 3 &&
            _account.withdrawCount < 10 &&
            timeDifference <= 1 days
        ) {
            return true;
        }

        return false;
    }

    function getServiceCharge(
        Account storage _account,
        uint256 _currentWithdrawalTime
    ) internal view returns (uint256) {
        if (!_account.isSavingsAccount) {
            return 0;
        }

        uint256 withdrawCount = _account.withdrawCount;
        uint256 serviceCharge = 0;

        if (withdrawCount >= 3) {
            uint256 timeDifference = _currentWithdrawalTime -
                _account.lastWithdrawTime;
            if (
                withdrawCount >= 3 &&
                withdrawCount < 10 &&
                timeDifference <= 1 days
            ) {
                serviceCharge = 150;
            } else {
                serviceCharge = 250;
            }
        }

        return serviceCharge;
    }

    function getLoanInterestRate(uint256 _loanType)
        internal
        pure
        returns (uint256)
    {
        if (_loanType == 1) {
            return 9;
        } else if (_loanType == 2) {
            return 6;
        } else if (_loanType == 3) {
            return 7;
        } else if (_loanType == 4) {
            return 4;
        } else if (_loanType == 5) {
            return 2;
        } else {
            revert("Invalid loan type");
        }
    }

    function getLoanTypeDescription(uint256 _loanInterestRate)
        internal
        pure
        returns (string memory)
    {
        if (_loanInterestRate == 9) {
            return "Personal Loan";
        } else if (_loanInterestRate == 6) {
            return "Business Loan";
        } else if (_loanInterestRate == 7) {
            return "Education Loan";
        } else if (_loanInterestRate == 4) {
            return "Home Loan";
        } else if (_loanInterestRate == 2) {
            return "Car Loan";
        } else {
            revert("Invalid loan interest rate");
        }
    }

    function calculateLoanRepaymentAmount(
        uint256 _loanAmount,
        uint256 _loanInterestRate
    ) internal pure returns (uint256) {
        uint256 interestAmount = (_loanAmount * _loanInterestRate) / 100;
        return _loanAmount + interestAmount;
    }
}
