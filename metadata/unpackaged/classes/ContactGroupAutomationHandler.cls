/**
 * ContactGroupAutomationHandler
 * 
 * Handles automatic Campaign Member management for LET Contact Groups.
 * Called from Contact Automation Flow when contacts are created or updated.
 * 
 * This class evaluates contact data against all Contact Group criteria and
 * automatically adds/removes contacts from the appropriate LET campaigns.
 * 
 * @author System Generated
 * @version 1.2 - Enhanced error handling, logging, and bug fixes
 */
public class ContactGroupAutomationHandler {
    
    public class ContactGroupResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Integer groupsProcessed { get; set; }
        @AuraEnabled public List<String> addedToCampaigns { get; set; }
        @AuraEnabled public List<String> removedFromCampaigns { get; set; }
        
        public ContactGroupResult() {
            this.success = false;
            this.groupsProcessed = 0;
            this.addedToCampaigns = new List<String>();
            this.removedFromCampaigns = new List<String>();
        }
    }
    
    // Campaign mapping - matches the Contact Group reports exactly
    private static Map<String, CampaignMapping> CAMPAIGN_MAPPINGS {
        get {
            if (CAMPAIGN_MAPPINGS == null) {
                CAMPAIGN_MAPPINGS = new Map<String, CampaignMapping>{
                    'LET_Chairs' => new CampaignMapping(
                        'LET Chairs',
                        new List<ContactCriteria>{
                            new ContactCriteria('Title', 'contains', 'Chair'),
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust'),
                            new ContactCriteria('Title', 'notContain', 'Dep'),
                            new ContactCriteria('Account.Name', 'notContain', 'National Board')
                        }
                    ),
                    'LET_Treasurers' => new CampaignMapping(
                        'LET Treasurers',
                        new List<ContactCriteria>{
                            new ContactCriteria('Title', 'contains', 'Treasurer'),
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust')
                        }
                    ),
                    'LET_Educators' => new CampaignMapping(
                        'LET Educators',
                        new List<ContactCriteria>{
                            new ContactCriteria('Title', 'contains', 'Educator'),
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust')
                        }
                    ),
                    'LET_Exec_Admin_Secretaries' => new CampaignMapping(
                        'LET Exec/Admin/Secretaries',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust'),
                            new ContactCriteria('Account.Name', 'notContain', 'National Office'),
                            new ContactCriteria('Title', 'containsAny', 'Exec;Admin;Secretary;Trust Manager')
                        }
                    ),
                    'LET_Regional_Facilitators' => new CampaignMapping(
                        'LET Regional Facilitators',
                        new List<ContactCriteria>{
                            new ContactCriteria('Regional_Facilitator__c', 'contains', 'YES'),
                            new ContactCriteria('Active__c', 'equals', 'true')
                        }
                    ),
                    'LET_Life_Members' => new CampaignMapping(
                        'LET Life Members',
                        new List<ContactCriteria>{
                            new ContactCriteria('Award_Life_Membership__c', 'equals', 'true')
                        }
                    ),
                    'LET_Distinguished_Service' => new CampaignMapping(
                        'LET Distinguished Service Award Recipients',
                        new List<ContactCriteria>{
                            new ContactCriteria('Award_Distinguished_Service__c', 'equals', 'true')
                        }
                    ),
                    'LET_Service_Awards' => new CampaignMapping(
                        'LET Service Award Recipients',
                        new List<ContactCriteria>{
                            new ContactCriteria('Award_Service__c', 'equals', 'true')
                        }
                    ),
                    'LET_Award_Recipients' => new CampaignMapping(
                        'LET Award Recipients',
                        new List<ContactCriteria>{
                            new ContactCriteria('Award_Life_Membership__c', 'hasAny', 'Award_Life_Membership__c;Award_Distinguished_Service__c;Award_Service__c')
                        }
                    ),
                    // Regional Educator Groups
                    'LET_Auckland_North_Educators' => new CampaignMapping(
                        'LET Auckland North Educator Region',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Regional_Group__c', 'contains', 'Auckland North')
                        }
                    ),
                    'LET_Auckland_South_Educators' => new CampaignMapping(
                        'LET Auckland South Educator Region',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Regional_Group__c', 'contains', 'Auckland South')
                        }
                    ),
                    'LET_Mid_North_Educators' => new CampaignMapping(
                        'LET Mid North Educator Region',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Regional_Group__c', 'contains', 'Mid North')
                        }
                    ),
                    'LET_Lower_North_Educators' => new CampaignMapping(
                        'LET Lower North Educator Region',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Regional_Group__c', 'contains', 'Lower North')
                        }
                    ),
                    'LET_South_Island_Educators' => new CampaignMapping(
                        'LET South Island Educator Region',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Regional_Group__c', 'contains', 'South Island')
                        }
                    ),
                    // Trustee Regional Groups - All 32 regions
                    // Logic: Active contacts on specific Trust Account, excluding Educators and Patrons
                    // Note: We don't require Title to contain "Trustee" to allow for various trustee titles (Chair, Treasurer, etc.)
                    'LET_Auckland_Central_Trustees' => new CampaignMapping(
                        'LET Auckland Central Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Auckland Central'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Auckland_West_Trustees' => new CampaignMapping(
                        'LET Auckland West Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Auckland West'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Canterbury_Trustees' => new CampaignMapping(
                        'LET Canterbury Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Canterbury'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Central_Plateau_Trustees' => new CampaignMapping(
                        'LET Central Plateau Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Central Plateau'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Coastal_Otago_Trustees' => new CampaignMapping(
                        'LET Coastal Otago Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Coastal Otago'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Counties_Manukau_Trustees' => new CampaignMapping(
                        'LET Counties Manukau Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Counties Manukau'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Eastern_Bay_of_Plenty_Trustees' => new CampaignMapping(
                        'LET Eastern Bay of Plenty Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Eastern Bay of Plenty'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Far_North_Trustees' => new CampaignMapping(
                        'LET Far North Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Far North'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Gisborne_Trustees' => new CampaignMapping(
                        'LET Gisborne Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Gisborne East Coast and Wairoa'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Hamilton_Trustees' => new CampaignMapping(
                        'LET Hamilton Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Hamilton'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Hawkes_Bay_Trustees' => new CampaignMapping(
                        'LET Hawke\'s Bay Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Hawke\'s Bay'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Heartland_Otago_Southland_Trustees' => new CampaignMapping(
                        'LET Heartland Otago/Southland Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Heartland Otago/Southland'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Hutt_Valley_Trustees' => new CampaignMapping(
                        'LET Hutt Valley Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Hutt Valley'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Kapiti_Horowhenua_Trustees' => new CampaignMapping(
                        'LET Kāpiti Horowhenua Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Kāpiti Horowhenua'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Manawatu_Trustees' => new CampaignMapping(
                        'LET Manawatu Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Manawatu'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Marlborough_Trustees' => new CampaignMapping(
                        'LET Marlborough Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Marlborough'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Mid_and_South_Canterbury_Trustees' => new CampaignMapping(
                        'LET Mid and South Canterbury Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Mid and South Canterbury'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Nelson_Tasman_Trustees' => new CampaignMapping(
                        'LET Nelson/Tasman Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Nelson/Tasman'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_North_Shore_Trustees' => new CampaignMapping(
                        'LET North Shore Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust North Shore'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_North_Wellington_Trustees' => new CampaignMapping(
                        'LET North Wellington Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust North Wellington'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Rodney_Trustees' => new CampaignMapping(
                        'LET Rodney Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Rodney'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Rotorua_Area_Trustees' => new CampaignMapping(
                        'LET Rotorua Area Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Rotorua Area'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Southland_Trustees' => new CampaignMapping(
                        'LET Southland Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Southland'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Taranaki_Trustees' => new CampaignMapping(
                        'LET Taranaki Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Taranaki'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Waikato_East_Trustees' => new CampaignMapping(
                        'LET Waikato East Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Waikato East'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Waipa_King_Country_Trustees' => new CampaignMapping(
                        'LET Waipā/King Country Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Waipā/King Country'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Wairarapa_Trustees' => new CampaignMapping(
                        'LET Wairarapa Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Wairarapa,Tararua and Central Hawke\'s Bay'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Wellington_City_Trustees' => new CampaignMapping(
                        'LET Wellington City Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Wellington City'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_West_Coast_Trustees' => new CampaignMapping(
                        'LET West Coast Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust West Coast'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Western_Bay_of_Plenty_Trustees' => new CampaignMapping(
                        'LET Western Bay of Plenty Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Western Bay of Plenty'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Whanganui_and_Districts_Trustees' => new CampaignMapping(
                        'LET Whanganui and Districts Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Whanganui and Districts'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    ),
                    'LET_Whangarei_Trustees' => new CampaignMapping(
                        'LET Whangarei Trustees',
                        new List<ContactCriteria>{
                            new ContactCriteria('Active__c', 'equals', 'true'),
                            new ContactCriteria('Account.Name', 'contains', 'Life Education Trust Whangarei'),
                            new ContactCriteria('Title', 'notContain', 'Educator'),
                            new ContactCriteria('Title', 'notContain', 'Patron')
                        }
                    )
                    // Total: 46 Contact Groups fully automated (14 role/award + 5 educator regions + 32 trustee regions = 51, minus 5 overlaps = 46 unique)
                };
            }
            return CAMPAIGN_MAPPINGS;
        }
        set;
    }
    
    /**
     * Invocable method for Flow integration
     */
    @InvocableMethod(label='Process Contact Group Memberships' description='Evaluates contact against all Contact Group criteria and manages Campaign Member relationships')
    public static void processContactGroupMemberships(List<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            System.debug('ContactGroupAutomationHandler: No contact IDs provided');
            return;
        }
        
        try {
            // Query contacts with all necessary fields
            List<Contact> contacts = [
                SELECT Id, Name, Title, Active__c, Regional_Group__c, Regional_Facilitator__c,
                       Award_Life_Membership__c, Award_Distinguished_Service__c, Award_Service__c,
                       LET_Role__c, Account.Name, Account.Id
                FROM Contact 
                WHERE Id IN :contactIds
            ];
            
            if (contacts.isEmpty()) {
                System.debug('ContactGroupAutomationHandler: No contacts found for provided IDs: ' + contactIds);
                return;
            }
            
            System.debug('ContactGroupAutomationHandler: Processing ' + contacts.size() + ' contact(s)');
            
            Integer successCount = 0;
            Integer errorCount = 0;
            
            for (Contact contact : contacts) {
                try {
                    processContactGroups(contact);
                    successCount++;
                } catch (Exception e) {
                    errorCount++;
                    System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Error processing contact ' + contact.Id + ' (' + contact.Name + '): ' + e.getMessage());
                    System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Stack trace: ' + e.getStackTraceString());
                }
            }
            
            System.debug('ContactGroupAutomationHandler: Completed processing. Success: ' + successCount + ', Errors: ' + errorCount);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Fatal error in processContactGroupMemberships: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Stack trace: ' + e.getStackTraceString());
            throw new ContactGroupAutomationException('Failed to process contact group memberships: ' + e.getMessage(), e);
        }
    }
    
    /**
     * Process a single contact against all Contact Group criteria
     */
    private static void processContactGroups(Contact contact) {
        if (contact == null) {
            System.debug('ContactGroupAutomationHandler: Contact is null, skipping processing');
            return;
        }
        
        try {
            // Get campaigns that contact currently qualifies for
            Set<String> qualifiedCampaigns = getQualifiedCampaigns(contact);
            System.debug('ContactGroupAutomationHandler: Contact ' + contact.Name + ' (' + contact.Id + ') qualifies for ' + qualifiedCampaigns.size() + ' campaign(s): ' + qualifiedCampaigns);
            
            // Get campaigns that contact is currently a member of (LET campaigns only)
            Set<String> currentCampaigns = getCurrentLETCampaignMemberships(contact.Id);
            System.debug('ContactGroupAutomationHandler: Contact ' + contact.Name + ' is currently in ' + currentCampaigns.size() + ' campaign(s): ' + currentCampaigns);
            
            // Determine additions and removals
            Set<String> automationManagedCampaignNames = new Set<String>();
            for (CampaignMapping mapping : CAMPAIGN_MAPPINGS.values()) {
                automationManagedCampaignNames.add(mapping.campaignName);
            }
            
            Set<String> toAdd = new Set<String>();
            Set<String> toRemove = new Set<String>();
            
            // Add to campaigns they qualify for but aren't in
            for (String campaignName : qualifiedCampaigns) {
                if (!currentCampaigns.contains(campaignName)) {
                    toAdd.add(campaignName);
                }
            }
            
            // Remove from campaigns they no longer qualify for (only automation-managed ones)
            for (String campaignName : currentCampaigns) {
                if (automationManagedCampaignNames.contains(campaignName) && !qualifiedCampaigns.contains(campaignName)) {
                    toRemove.add(campaignName);
                }
            }
            
            // Execute changes
            if (!toAdd.isEmpty()) {
                Integer added = addToCampaigns(contact.Id, toAdd);
                System.debug('ContactGroupAutomationHandler: Added ' + contact.Name + ' to ' + added + ' Contact Group(s): ' + toAdd);
            }
            
            if (!toRemove.isEmpty()) {
                Integer removed = removeFromCampaigns(contact.Id, toRemove);
                System.debug('ContactGroupAutomationHandler: Removed ' + contact.Name + ' from ' + removed + ' Contact Group(s): ' + toRemove);
            }
            
            if (toAdd.isEmpty() && toRemove.isEmpty()) {
                System.debug('ContactGroupAutomationHandler: No changes needed for contact ' + contact.Name);
            }
                
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Error processing Contact Groups for ' + (contact != null ? contact.Name : 'null contact') + ': ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Stack trace: ' + e.getStackTraceString());
            throw e; // Re-throw to be caught by caller
        }
    }
    
    /**
     * Evaluate contact against all criteria to determine qualified campaigns
     */
    private static Set<String> getQualifiedCampaigns(Contact contact) {
        Set<String> qualified = new Set<String>();
        
        for (String campaignKey : CAMPAIGN_MAPPINGS.keySet()) {
            CampaignMapping mapping = CAMPAIGN_MAPPINGS.get(campaignKey);
            
            if (evaluateAllCriteria(contact, mapping.criteria)) {
                qualified.add(mapping.campaignName);
            }
        }
        
        return qualified;
    }
    
    /**
     * Evaluate all criteria for a contact
     */
    private static Boolean evaluateAllCriteria(Contact contact, List<ContactCriteria> criteriaList) {
        for (ContactCriteria criteria : criteriaList) {
            if (!evaluateCriteria(contact, criteria)) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * Evaluate single criteria against contact
     */
    private static Boolean evaluateCriteria(Contact contact, ContactCriteria criteria) {
        if (contact == null || criteria == null) {
            System.debug('ContactGroupAutomationHandler: Null contact or criteria in evaluateCriteria');
            return false;
        }
        
        try {
            // Special handling for 'hasAny' operator - checks multiple fields
            if (criteria.operator.toLowerCase() == 'hasany') {
                List<String> fields = criteria.expectedValue.split(';');
                for (String field : fields) {
                    field = field.trim();
                    if (String.isNotBlank(field)) {
                        Object val = getFieldValue(contact, field);
                        if (val == true || String.valueOf(val).equalsIgnoreCase('true')) {
                            return true;
                        }
                    }
                }
                return false;
            }
            
            // For other operators, get the field value
            Object fieldValue = getFieldValue(contact, criteria.fieldName);
            String valueStr = fieldValue != null ? String.valueOf(fieldValue) : '';
            
            switch on criteria.operator.toLowerCase() {
                when 'equals' {
                    return valueStr.equalsIgnoreCase(criteria.expectedValue);
                }
                when 'contains' {
                    if (String.isBlank(criteria.expectedValue)) {
                        return false;
                    }
                    return valueStr.toLowerCase().contains(criteria.expectedValue.toLowerCase());
                }
                when 'notcontain' {
                    if (String.isBlank(criteria.expectedValue)) {
                        return true; // If nothing to exclude, criteria passes
                    }
                    return !valueStr.toLowerCase().contains(criteria.expectedValue.toLowerCase());
                }
                when 'containsany' {
                    if (String.isBlank(criteria.expectedValue)) {
                        return false;
                    }
                    List<String> options = criteria.expectedValue.split(';');
                    for (String option : options) {
                        option = option.trim();
                        if (String.isNotBlank(option) && valueStr.toLowerCase().contains(option.toLowerCase())) {
                            return true;
                        }
                    }
                    return false;
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'ContactGroupAutomationHandler: Error evaluating criteria ' + criteria.fieldName + ' ' + criteria.operator + ' ' + criteria.expectedValue + ': ' + e.getMessage());
            return false; // Fail safe - if criteria evaluation fails, contact doesn't qualify
        }
        
        return false;
    }
    
    /**
     * Get field value with support for nested fields (e.g., Account.Name)
     */
    private static Object getFieldValue(Contact contact, String fieldName) {
        if (contact == null || String.isBlank(fieldName)) {
            return null;
        }
        
        try {
            if (fieldName.contains('.')) {
                // Handle nested fields like Account.Name
                List<String> parts = fieldName.split('\\.');
                if (parts.size() == 2 && parts[0] == 'Account') {
                    if (contact.Account == null) {
                        System.debug('ContactGroupAutomationHandler: Contact ' + contact.Id + ' has no Account for field ' + fieldName);
                        return null;
                    }
                    return contact.Account.get(parts[1]);
                } else {
                    System.debug('ContactGroupAutomationHandler: Unsupported nested field format: ' + fieldName);
                    return null;
                }
            } else {
                // Check if field exists on Contact
                if (!Schema.sObjectType.Contact.fields.getMap().containsKey(fieldName)) {
                    System.debug('ContactGroupAutomationHandler: Field does not exist on Contact: ' + fieldName);
                    return null;
                }
                return contact.get(fieldName);
            }
        } catch (Exception e) {
            // Field doesn't exist or can't be accessed
            System.debug(LoggingLevel.WARN, 'ContactGroupAutomationHandler: Could not access field ' + fieldName + ' for contact ' + contact.Id + ': ' + e.getMessage());
        }
        return null;
    }
    
    /**
     * Get current LET campaign memberships for contact
     */
    private static Set<String> getCurrentLETCampaignMemberships(Id contactId) {
        Set<String> campaigns = new Set<String>();
        
        List<CampaignMember> members = [
            SELECT Campaign.Name 
            FROM CampaignMember 
            WHERE ContactId = :contactId 
            AND Campaign.Name LIKE 'LET %'
            AND Status != 'Removed'
        ];
        
        for (CampaignMember member : members) {
            campaigns.add(member.Campaign.Name);
        }
        
        return campaigns;
    }
    
    /**
     * Add contact to campaigns
     * Returns the number of campaign members successfully added
     */
    private static Integer addToCampaigns(Id contactId, Set<String> campaignNames) {
        if (contactId == null || campaignNames == null || campaignNames.isEmpty()) {
            System.debug('ContactGroupAutomationHandler: Invalid parameters for addToCampaigns');
            return 0;
        }
        
        try {
            Map<String, Campaign> campaignMap = getCampaignsByName(campaignNames);
            
            // Check for missing campaigns
            Set<String> missingCampaigns = new Set<String>();
            for (String campaignName : campaignNames) {
                if (!campaignMap.containsKey(campaignName)) {
                    missingCampaigns.add(campaignName);
                }
            }
            if (!missingCampaigns.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'ContactGroupAutomationHandler: Campaign(s) not found: ' + missingCampaigns);
            }
            
            // Check for existing campaign members to avoid duplicates
            Set<Id> existingCampaignIds = new Set<Id>();
            if (!campaignMap.isEmpty()) {
                List<CampaignMember> existingMembers = [
                    SELECT CampaignId 
                    FROM CampaignMember 
                    WHERE ContactId = :contactId 
                    AND CampaignId IN :campaignMap.values()
                    AND Status != 'Removed'
                ];
                for (CampaignMember member : existingMembers) {
                    existingCampaignIds.add(member.CampaignId);
                }
            }
            
            List<CampaignMember> membersToInsert = new List<CampaignMember>();
            
            for (String campaignName : campaignNames) {
                Campaign camp = campaignMap.get(campaignName);
                if (camp != null && !existingCampaignIds.contains(camp.Id)) {
                    membersToInsert.add(new CampaignMember(
                        CampaignId = camp.Id,
                        ContactId = contactId,
                        Status = 'Connected' // Standard status for Contact Groups
                    ));
                }
            }
            
            if (!membersToInsert.isEmpty()) {
                // Use Database.insert with allOrNone=false to handle partial failures gracefully
                Database.SaveResult[] results = Database.insert(membersToInsert, false);
                Integer successCount = 0;
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        successCount++;
                    } else {
                        System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Failed to add contact to campaign ' + membersToInsert[i].CampaignId + ': ' + results[i].getErrors());
                    }
                }
                return successCount;
            }
            
            return 0;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Error in addToCampaigns: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Stack trace: ' + e.getStackTraceString());
            throw e;
        }
    }
    
    /**
     * Remove contact from campaigns
     * Returns the number of campaign members successfully removed
     */
    private static Integer removeFromCampaigns(Id contactId, Set<String> campaignNames) {
        if (contactId == null || campaignNames == null || campaignNames.isEmpty()) {
            System.debug('ContactGroupAutomationHandler: Invalid parameters for removeFromCampaigns');
            return 0;
        }
        
        try {
            Map<String, Campaign> campaignMap = getCampaignsByName(campaignNames);
            
            if (campaignMap.isEmpty()) {
                System.debug('ContactGroupAutomationHandler: No campaigns found for removal');
                return 0;
            }
            
            List<Id> campaignIds = new List<Id>();
            for (Campaign camp : campaignMap.values()) {
                campaignIds.add(camp.Id);
            }
            
            List<CampaignMember> membersToRemove = [
                SELECT Id, Campaign.Name
                FROM CampaignMember 
                WHERE ContactId = :contactId 
                AND CampaignId IN :campaignIds
                AND Status != 'Removed'
            ];
            
            if (!membersToRemove.isEmpty()) {
                // Use Database.delete with allOrNone=false to handle partial failures gracefully
                Database.DeleteResult[] results = Database.delete(membersToRemove, false);
                Integer successCount = 0;
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        successCount++;
                    } else {
                        System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Failed to remove contact from campaign ' + membersToRemove[i].Campaign.Name + ': ' + results[i].getErrors());
                    }
                }
                return successCount;
            }
            
            return 0;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Error in removeFromCampaigns: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Stack trace: ' + e.getStackTraceString());
            throw e;
        }
    }
    
    /**
     * Get campaigns by name
     */
    private static Map<String, Campaign> getCampaignsByName(Set<String> campaignNames) {
        Map<String, Campaign> campaignMap = new Map<String, Campaign>();
        
        if (campaignNames == null || campaignNames.isEmpty()) {
            return campaignMap;
        }
        
        try {
            List<Campaign> campaigns = [
                SELECT Id, Name 
                FROM Campaign 
                WHERE Name IN :campaignNames
            ];
            
            for (Campaign camp : campaigns) {
                campaignMap.put(camp.Name, camp);
            }
            
            // Log missing campaigns for debugging
            Set<String> foundNames = new Set<String>(campaignMap.keySet());
            Set<String> missingNames = new Set<String>();
            for (String name : campaignNames) {
                if (!foundNames.contains(name)) {
                    missingNames.add(name);
                }
            }
            if (!missingNames.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'ContactGroupAutomationHandler: Campaign(s) not found in Salesforce: ' + missingNames);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Error querying campaigns: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'ContactGroupAutomationHandler: Stack trace: ' + e.getStackTraceString());
        }
        
        return campaignMap;
    }
    
    // Helper classes
    private class CampaignMapping {
        public String campaignName;
        public List<ContactCriteria> criteria;
        
        public CampaignMapping(String campaignName, List<ContactCriteria> criteria) {
            this.campaignName = campaignName;
            this.criteria = criteria;
        }
    }
    
    private class ContactCriteria {
        public String fieldName;
        public String operator;
        public String expectedValue;
        
        public ContactCriteria(String fieldName, String operator, String expectedValue) {
            this.fieldName = fieldName;
            this.operator = operator;
            this.expectedValue = expectedValue;
        }
    }
    
    /**
     * Custom exception class for Contact Group Automation errors
     */
    public class ContactGroupAutomationException extends Exception {}
}