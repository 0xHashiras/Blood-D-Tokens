// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract BloodD is AccessControl{

    address public owner;
    uint256 public totalBloodDonatedInMl;
    uint256 donorIdCounter = 1;
    uint256 appIdCounter = 1;

    // enum BloodGroup {
    //     A+, A-, B+, B-, O+, O-, AB+, AB-
    // }

    enum Status {
        ApplicationSubmitted, 
        ApplicationValidating, ApplicationApproved, ApplicationRejected,
        PhysicalVerificationApproved, PhysicalVerificationFailed,
        OngoingScreeningTest, ScreeningTestFailed, ScreeningTestApprovedAndMovedToStorage
    }    

    struct DonorData{
        bytes32 _donorDataHash;
        uint256 _enrolledTimestamp;
        string _bloodGroup;
        uint256 _totalBloodDonatedInMl;
        address _walletAddress;
        bool _isVerified;
    }
    mapping(uint256 => DonorData) public donorId2Data;
    mapping(bytes32 => uint256) public verifiedDataHash2Id;
    mapping(bytes32 => uint256) public AllDataHash2Id;
    mapping(address => uint256) public address2DonorID;

    struct Application{
        uint256 _donorId;
        string _formURL;
        string _bloodGroup;
        uint256 _appliedTime;
        uint256 _collectionTime;
        uint256 _closedTime;
        uint256 _bloodDonated;
        Status _status;
    }
    mapping(uint256 => Application) public appId2Data;
    mapping(uint256=>uint256) public donorId2activeAppId;


    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");
    bytes32 public constant PHYSICAL_VERIFIER_ROLE = keccak256("PHYSICAL_VERIFIER_ROLE");
    bytes32 public constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");
    bytes32 public constant SCREENER_ROLE = keccak256("SCREENER_ROLE");

    constructor(){
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(APPROVER_ROLE, msg.sender);
        _grantRole(PHYSICAL_VERIFIER_ROLE, msg.sender);
        _grantRole(COLLECTOR_ROLE, msg.sender);
        _grantRole(SCREENER_ROLE, msg.sender);
        owner = msg.sender;
    }

    function enrollDonor(bytes32  _donorDataHash, string memory _bloodGroup, address wallet) external returns (uint256){
        require(verifiedDataHash2Id[_donorDataHash] == 0, "Sorry, you have already enrolled");
        uint256 donorId = donorIdCounter;

        DonorData memory donorData = DonorData(_donorDataHash, block.timestamp, _bloodGroup, 0, wallet, false);
        donorId2Data[donorId] = donorData;

        AllDataHash2Id[_donorDataHash] = donorId ;
        address2DonorID[wallet] = donorId;
        
        donorIdCounter++;

        return donorId;
    }

    function applyforBloodDonation(uint256 _donorId, string calldata _formURL) external returns (uint256){
        require(donorId2Data[_donorId]._donorDataHash != 0, "Please Enroll before applying!");
        require(donorId2activeAppId[_donorId] == 0, "Application already in progress");
        require(msg.sender == donorId2Data[_donorId]._walletAddress || msg.sender == owner, "Unauthorized access");

        string memory _bloodGroup = donorId2Data[_donorId]._bloodGroup;
        uint256 appId = appIdCounter;

        Application memory app = Application(_donorId, _formURL, _bloodGroup, block.timestamp, 0, 0, 0, Status.ApplicationSubmitted);
        appId2Data[appId] = app;
        donorId2activeAppId[_donorId] = appId;

        appIdCounter++;

        return appId;
    }


    // ----Approver----: 

    // Application form Approval
    function validateApplication(uint256 _appId, bool _status) external onlyRole(APPROVER_ROLE){
        require(appId2Data[_appId]._status == Status.ApplicationSubmitted, "Invalid Application Id");

        if (_status) 
            appId2Data[_appId]._status = Status.ApplicationApproved;
        else 
            appId2Data[_appId]._status = Status.ApplicationRejected;

    }


    // ----Physical Verifer----:

    // User Physical Data Verification at blood bank 
    function validateHashOfUser(uint256 _appId, bytes32 _physicalHash) external view onlyRole(PHYSICAL_VERIFIER_ROLE) returns(bool){
        require(appId2Data[_appId]._donorId != 0 , "Invalid Application Id");
        uint256 donorId = appId2Data[_appId]._donorId;
        bytes32 storedhash = donorId2Data[donorId]._donorDataHash ;
        if (storedhash == _physicalHash)
            return true;
        return false;
    }

    // Verifier calls this function , lastly
    function validatePhysicalUserData(uint256 _appId, bool _status ) external onlyRole(PHYSICAL_VERIFIER_ROLE){
        require(appId2Data[_appId]._status == Status.ApplicationApproved, "Invalid Application Id");

        if (_status) 
            appId2Data[_appId]._status = Status.PhysicalVerificationApproved;
        else 
            appId2Data[_appId]._status = Status.PhysicalVerificationFailed;

        uint256 donorId = appId2Data[_appId]._donorId;
        bytes32 storedhash = donorId2Data[donorId]._donorDataHash ;
        if (verifiedDataHash2Id[storedhash] == 0)
            verifiedDataHash2Id[storedhash] = AllDataHash2Id[storedhash];
    }


    // ----Collector----:

    // collectBloodSample
    function collectBloodSample(uint256 _appId, uint256 _bloodDonated) external onlyRole(COLLECTOR_ROLE){
        require(appId2Data[_appId]._status == Status.PhysicalVerificationApproved, "Invalid Application Id");
        require(_bloodDonated > 0, "Invalid Amount passed");

        donorId2Data[ appId2Data[_appId]._donorId ]._totalBloodDonatedInMl += _bloodDonated;
        totalBloodDonatedInMl += _bloodDonated;

        appId2Data[_appId]._bloodDonated = _bloodDonated;
        appId2Data[_appId]._collectionTime = block.timestamp;

        appId2Data[_appId]._status = Status.OngoingScreeningTest;
    }


    // ----Screener----: 

    // Screening Test results
    function validateScreeningTest(uint256 _appId, bool _status) external onlyRole(COLLECTOR_ROLE){
        require(appId2Data[_appId]._status == Status.OngoingScreeningTest, "Invalid Application Id");

        if (_status){ 
            appId2Data[_appId]._status = Status.ScreeningTestApprovedAndMovedToStorage;
            uint256 donorId = appId2Data[_appId]._donorId;
            donorId2activeAppId[donorId] = 0;
        }
        else 
            appId2Data[_appId]._status = Status.ScreeningTestFailed;

        appId2Data[_appId]._closedTime = block.timestamp;
    }
    



    // Overrides required
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool){
        return super.supportsInterface(interfaceId);
    }

    
}
