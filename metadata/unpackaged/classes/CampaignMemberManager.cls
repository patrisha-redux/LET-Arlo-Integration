/**
 * CampaignMemberManager
 *
 * Manages campaign member creation for the Arlo integration.
 * Handles adding contacts to campaigns, checking for duplicates,
 * and bulk insert operations.
 */
public with sharing class CampaignMemberManager {

    /**
     * Wrapper class to hold contact and event information
     */
    public class ContactEventInfo {
        public Id contactId { get; set; }
        public String contactUuid { get; set; }
        public String contactEmail { get; set; }
        public String eventName { get; set; }
        public String eventCode { get; set; }

        public ContactEventInfo() {}

        public ContactEventInfo(Id contactId, String eventName) {
            this.contactId = contactId;
            this.eventName = eventName;
        }
    }

    /**
     * Result class for campaign member operations
     */
    public class AddMembersResult {
        public Integer totalProcessed { get; set; }
        public Integer membersAdded { get; set; }
        public Integer alreadyMembers { get; set; }
        public Integer noCampaignMatch { get; set; }
        public Integer campaignNotFound { get; set; }
        public List<String> errors { get; set; }

        public AddMembersResult() {
            this.totalProcessed = 0;
            this.membersAdded = 0;
            this.alreadyMembers = 0;
            this.noCampaignMatch = 0;
            this.campaignNotFound = 0;
            this.errors = new List<String>();
        }
    }

    /**
     * Add contacts to campaigns based on their event registrations
     * Uses ArloEventRegistrationSync.ContactEventWrapper format for backward compatibility
     *
     * @param contactEventList List of contact-event wrappers
     * @param syncedContactMap Map of Salesforce Contact Id to Contact record
     * @return Result object with counts and any errors
     */
    public static AddMembersResult addContactsToCampaigns(
        List<ArloEventRegistrationSync.ContactEventWrapper> contactEventList,
        Map<Id, Contact> syncedContactMap
    ) {
        AddMembersResult result = new AddMembersResult();

        if (contactEventList == null || contactEventList.isEmpty()) {
            return result;
        }

        // Get campaign name to ID mapping
        Map<String, Id> campaignNameToIdMap = EventCampaignMapper.getCampaignNameToIdMap();

        if (campaignNameToIdMap.isEmpty()) {
            result.errors.add('No NHM campaigns found in Salesforce');
            return result;
        }

        // Build wrapper maps for matching
        Map<String, List<ArloEventRegistrationSync.ContactEventWrapper>> uuidToWrappersMap =
            new Map<String, List<ArloEventRegistrationSync.ContactEventWrapper>>();
        Map<String, List<ArloEventRegistrationSync.ContactEventWrapper>> emailToWrappersMap =
            new Map<String, List<ArloEventRegistrationSync.ContactEventWrapper>>();

        // Build sets of wrapper identifiers
        Set<String> wrapperUuids = new Set<String>();
        Set<String> wrapperEmails = new Set<String>();

        for (ArloEventRegistrationSync.ContactEventWrapper wrapper : contactEventList) {
            if (wrapper.contact != null) {
                if (String.isNotBlank(wrapper.contact.contactId)) {
                    String uuidKey = wrapper.contact.contactId.trim();
                    wrapperUuids.add(uuidKey);
                    if (!uuidToWrappersMap.containsKey(uuidKey)) {
                        uuidToWrappersMap.put(uuidKey, new List<ArloEventRegistrationSync.ContactEventWrapper>());
                    }
                    uuidToWrappersMap.get(uuidKey).add(wrapper);
                }
                if (String.isNotBlank(wrapper.contact.email)) {
                    String emailKey = wrapper.contact.email.toLowerCase().trim();
                    wrapperEmails.add(emailKey);
                    if (!emailToWrappersMap.containsKey(emailKey)) {
                        emailToWrappersMap.put(emailKey, new List<ArloEventRegistrationSync.ContactEventWrapper>());
                    }
                    emailToWrappersMap.get(emailKey).add(wrapper);
                }
            }
        }

        // Map Contact ID to Set of Campaign Names
        Map<Id, Set<String>> contactToCampaignsMap = new Map<Id, Set<String>>();

        for (Contact contact : syncedContactMap.values()) {
            String contactUuid = contact.Arlo_Contact_UUID__c != null ? contact.Arlo_Contact_UUID__c.trim() : '';
            String contactEmail = contact.Email != null ? contact.Email.toLowerCase().trim() : '';

            // Check if this contact has any wrappers
            Boolean hasWrapper = false;
            if (String.isNotBlank(contactUuid) && wrapperUuids.contains(contactUuid)) {
                hasWrapper = true;
            } else if (String.isNotBlank(contactEmail) && wrapperEmails.contains(contactEmail)) {
                hasWrapper = true;
            }

            if (!hasWrapper) {
                continue;
            }

            // Get wrappers for this contact
            List<ArloEventRegistrationSync.ContactEventWrapper> wrappers =
                new List<ArloEventRegistrationSync.ContactEventWrapper>();

            if (String.isNotBlank(contactUuid) && uuidToWrappersMap.containsKey(contactUuid)) {
                wrappers.addAll(uuidToWrappersMap.get(contactUuid));
            }

            if (String.isNotBlank(contactEmail) && emailToWrappersMap.containsKey(contactEmail)) {
                for (ArloEventRegistrationSync.ContactEventWrapper w : emailToWrappersMap.get(contactEmail)) {
                    Boolean alreadyAdded = false;
                    for (ArloEventRegistrationSync.ContactEventWrapper existing : wrappers) {
                        if (existing.eventName == w.eventName && existing.eventCode == w.eventCode) {
                            alreadyAdded = true;
                            break;
                        }
                    }
                    if (!alreadyAdded) {
                        wrappers.add(w);
                    }
                }
            }

            if (wrappers.isEmpty()) {
                continue;
            }

            // Process wrappers and determine campaigns
            Set<String> campaignNames = new Set<String>();
            for (ArloEventRegistrationSync.ContactEventWrapper wrapper : wrappers) {
                result.totalProcessed++;

                if (String.isBlank(wrapper.eventName)) {
                    continue;
                }

                String campaignName = EventCampaignMapper.getCampaignNameForEvent(wrapper.eventName);
                if (String.isBlank(campaignName)) {
                    result.noCampaignMatch++;
                    continue;
                }

                if (!campaignNameToIdMap.containsKey(campaignName)) {
                    result.campaignNotFound++;
                    continue;
                }

                campaignNames.add(campaignName);
            }

            if (!campaignNames.isEmpty()) {
                contactToCampaignsMap.put(contact.Id, campaignNames);
            }
        }

        if (contactToCampaignsMap.isEmpty()) {
            return result;
        }

        // Get existing campaign members to avoid duplicates
        Set<Id> contactIds = contactToCampaignsMap.keySet();
        Set<Id> campaignIds = new Set<Id>(campaignNameToIdMap.values());

        Map<String, CampaignMember> existingMemberMap = new Map<String, CampaignMember>();
        List<CampaignMember> existingMembers = [
            SELECT ContactId, CampaignId
            FROM CampaignMember
            WHERE ContactId IN :contactIds AND CampaignId IN :campaignIds
        ];

        for (CampaignMember member : existingMembers) {
            String key = member.ContactId + '_' + member.CampaignId;
            existingMemberMap.put(key, member);
        }

        // Create new campaign members
        List<CampaignMember> membersToInsert = new List<CampaignMember>();

        for (Id contactId : contactToCampaignsMap.keySet()) {
            Set<String> campaignNames = contactToCampaignsMap.get(contactId);
            for (String campaignName : campaignNames) {
                Id campaignId = campaignNameToIdMap.get(campaignName);
                String memberKey = contactId + '_' + campaignId;

                if (existingMemberMap.containsKey(memberKey)) {
                    result.alreadyMembers++;
                } else {
                    membersToInsert.add(new CampaignMember(
                        ContactId = contactId,
                        CampaignId = campaignId,
                        Status = 'Responded'
                    ));
                }
            }
        }

        // Insert new campaign members
        if (!membersToInsert.isEmpty()) {
            try {
                insert membersToInsert;
                result.membersAdded = membersToInsert.size();
            } catch (Exception e) {
                result.errors.add('Error inserting campaign members: ' + e.getMessage());
            }
        }

        return result;
    }

    /**
     * Add a single contact to a campaign by event name
     *
     * @param contactId Salesforce Contact ID
     * @param eventName Event name to determine campaign
     * @return true if successfully added (or already a member)
     */
    public static Boolean addContactToCampaignByEvent(Id contactId, String eventName) {
        if (contactId == null || String.isBlank(eventName)) {
            return false;
        }

        String campaignName = EventCampaignMapper.getCampaignNameForEvent(eventName);
        if (String.isBlank(campaignName)) {
            return false;
        }

        return addContactToCampaign(contactId, campaignName);
    }

    /**
     * Add a contact to a specific campaign by name
     *
     * @param contactId Salesforce Contact ID
     * @param campaignName Exact campaign name
     * @return true if successfully added (or already a member)
     */
    public static Boolean addContactToCampaign(Id contactId, String campaignName) {
        if (contactId == null || String.isBlank(campaignName)) {
            return false;
        }

        // Get campaign ID
        Id campaignId = EventCampaignMapper.getCampaignIdByName(campaignName);
        if (campaignId == null) {
            return false;
        }

        // Check if already a member
        List<CampaignMember> existing = [
            SELECT Id
            FROM CampaignMember
            WHERE ContactId = :contactId AND CampaignId = :campaignId
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return true; // Already a member
        }

        // Add to campaign
        try {
            CampaignMember member = new CampaignMember(
                ContactId = contactId,
                CampaignId = campaignId,
                Status = 'Responded'
            );
            insert member;
            return true;
        } catch (Exception e) {
            System.debug('CampaignMemberManager: Error adding contact to campaign: ' + e.getMessage());
            return false;
        }
    }

    /**
     * Get current NHM campaign memberships for a contact
     *
     * @param contactId Salesforce Contact ID
     * @return List of campaign names the contact is a member of
     */
    public static List<String> getContactNhmCampaigns(Id contactId) {
        List<String> campaignNames = new List<String>();

        if (contactId == null) {
            return campaignNames;
        }

        List<CampaignMember> members = [
            SELECT Campaign.Name
            FROM CampaignMember
            WHERE ContactId = :contactId AND Campaign.Name LIKE 'NHM - %'
        ];

        for (CampaignMember member : members) {
            campaignNames.add(member.Campaign.Name);
        }

        return campaignNames;
    }

    /**
     * Check if a contact is a member of a specific campaign
     *
     * @param contactId Salesforce Contact ID
     * @param campaignName Campaign name to check
     * @return true if the contact is a member
     */
    public static Boolean isContactCampaignMember(Id contactId, String campaignName) {
        if (contactId == null || String.isBlank(campaignName)) {
            return false;
        }

        Id campaignId = EventCampaignMapper.getCampaignIdByName(campaignName);
        if (campaignId == null) {
            return false;
        }

        List<CampaignMember> members = [
            SELECT Id
            FROM CampaignMember
            WHERE ContactId = :contactId AND CampaignId = :campaignId
            LIMIT 1
        ];

        return !members.isEmpty();
    }
}