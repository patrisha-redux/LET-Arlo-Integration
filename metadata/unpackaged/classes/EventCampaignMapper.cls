/**
 * EventCampaignMapper
 *
 * Maps Arlo event names to Salesforce campaign names.
 * Handles keyword matching to determine which campaign a contact
 * should be added to based on their event registration.
 */
public with sharing class EventCampaignMapper {

    // Campaign name constants
    public static final String CAMPAIGN_ANXIETY = 'NHM - Anxiety';
    public static final String CAMPAIGN_DIGITAL_WELLBEING = 'NHM - Digital wellbeing';
    public static final String CAMPAIGN_SELF_CARE = 'NHM - Self-care';
    public static final String CAMPAIGN_NEURODIVERSITY = 'NHM - Neurodiversity';

    // All NHM campaign names
    public static final List<String> ALL_CAMPAIGN_NAMES = new List<String>{
        CAMPAIGN_ANXIETY,
        CAMPAIGN_DIGITAL_WELLBEING,
        CAMPAIGN_SELF_CARE,
        CAMPAIGN_NEURODIVERSITY
    };

    // Cached campaign ID map
    private static Map<String, Id> campaignNameToIdCache;

    /**
     * Get the campaign name for a given event name
     * Checks event name for keywords and maps to corresponding campaign
     *
     * @param eventName The name of the Arlo event
     * @return The campaign name, or null if no match
     */
    public static String getCampaignNameForEvent(String eventName) {
        if (String.isBlank(eventName)) {
            return null;
        }

        String eventNameUpper = eventName.toUpperCase();

        // Check for keywords in order of specificity (more specific first)
        // IMPORTANT: Check ANXIETY before NEURODIVERSITY to handle cases where event name might contain both
        if (eventNameUpper.contains('ANXIETY')) {
            return CAMPAIGN_ANXIETY;
        } else if (eventNameUpper.contains('DIGITAL') && (eventNameUpper.contains('WELLBEING') || eventNameUpper.contains('WELL-BEING'))) {
            return CAMPAIGN_DIGITAL_WELLBEING;
        } else if (eventNameUpper.contains('SELF-CARE') || eventNameUpper.contains('SELFCARE') || eventNameUpper.contains('SELF CARE')) {
            return CAMPAIGN_SELF_CARE;
        } else if (eventNameUpper.contains('NEURODIVERSITY') || eventNameUpper.contains('NEURO-DIVERSITY')) {
            return CAMPAIGN_NEURODIVERSITY;
        }

        return null;
    }

    /**
     * Get the Campaign SObject for a given event name
     *
     * @param eventName The name of the Arlo event
     * @return The Campaign record, or null if no match or campaign doesn't exist
     */
    public static Campaign getCampaignForEvent(String eventName) {
        String campaignName = getCampaignNameForEvent(eventName);
        if (String.isBlank(campaignName)) {
            return null;
        }

        Id campaignId = getCampaignIdByName(campaignName);
        if (campaignId == null) {
            return null;
        }

        return new Campaign(Id = campaignId, Name = campaignName);
    }

    /**
     * Get the Campaign ID for a given campaign name
     * Uses caching to avoid repeated queries
     *
     * @param campaignName The exact campaign name
     * @return The Campaign ID, or null if not found
     */
    public static Id getCampaignIdByName(String campaignName) {
        if (String.isBlank(campaignName)) {
            return null;
        }

        // Initialize cache if needed
        if (campaignNameToIdCache == null) {
            loadCampaignCache();
        }

        return campaignNameToIdCache.get(campaignName);
    }

    /**
     * Get a map of campaign names to IDs for all NHM campaigns
     * Uses caching to avoid repeated queries
     *
     * @return Map of campaign name to campaign ID
     */
    public static Map<String, Id> getCampaignNameToIdMap() {
        if (campaignNameToIdCache == null) {
            loadCampaignCache();
        }
        return new Map<String, Id>(campaignNameToIdCache);
    }

    /**
     * Check if a campaign exists by name
     *
     * @param campaignName The exact campaign name
     * @return true if the campaign exists
     */
    public static Boolean campaignExists(String campaignName) {
        return getCampaignIdByName(campaignName) != null;
    }

    /**
     * Get all NHM campaigns that exist in Salesforce
     *
     * @return List of Campaign records
     */
    public static List<Campaign> getAllNhmCampaigns() {
        return [
            SELECT Id, Name
            FROM Campaign
            WHERE Name IN :ALL_CAMPAIGN_NAMES
        ];
    }

    /**
     * Check if an event name matches any NHM campaign
     *
     * @param eventName The event name to check
     * @return true if the event name matches a campaign keyword
     */
    public static Boolean eventMatchesCampaign(String eventName) {
        return getCampaignNameForEvent(eventName) != null;
    }

    /**
     * Clear the campaign cache (useful for testing)
     */
    @TestVisible
    private static void clearCache() {
        campaignNameToIdCache = null;
    }

    /**
     * Load the campaign cache from the database
     */
    private static void loadCampaignCache() {
        campaignNameToIdCache = new Map<String, Id>();

        List<Campaign> campaigns = [
            SELECT Id, Name
            FROM Campaign
            WHERE Name IN :ALL_CAMPAIGN_NAMES
        ];

        for (Campaign camp : campaigns) {
            campaignNameToIdCache.put(camp.Name, camp.Id);
        }
    }
}