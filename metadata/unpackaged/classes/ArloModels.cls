/**
 * ArloModels - Data model classes for Arlo integration
 *
 * This class contains all the inner classes used to represent data structures
 * from the Arlo training management system. These models are used for syncing
 * contacts, events, registrations, and organisations between Arlo and Salesforce.
 *
 * @author Life Education
 * @date 2026
 */
public with sharing class ArloModels {

    /**
     * ArloContact - Represents a contact record from Arlo
     *
     * Contains the contact information including their unique identifier,
     * personal details, and associated organisation.
     */
    public virtual class ArloContact {
        /** The unique identifier (UUID) for the contact in Arlo */
        public String contactId { get; set; }

        /** The numeric contact ID from Arlo (legacy identifier) */
        public String numericContactId { get; set; }

        /** Contact's first name */
        public String firstName { get; set; }

        /** Contact's last name */
        public String lastName { get; set; }

        /** Contact's email address */
        public String email { get; set; }

        /** Contact's phone number */
        public String phone { get; set; }

        /** Contact's job title */
        public String title { get; set; }

        /** The ID of the contact's primary organisation in Arlo */
        public String organisationId { get; set; }

        /** The primary code for the contact's organisation */
        public String organisationCodePrimary { get; set; }

        /** The status of the contact in Arlo (e.g., Active, Inactive) */
        public String status { get; set; }
    }

    /**
     * ArloRegistration - Represents an event registration from Arlo
     *
     * Contains information about a contact's registration for a specific event,
     * including attendance status and consent preferences.
     */
    public class ArloRegistration {
        /** The unique identifier for the registration */
        public String registrationId { get; set; }

        /** The unique identifier (UUID) for the registration */
        public String uniqueIdentifier { get; set; }

        /** The ID of the contact who registered */
        public String contactId { get; set; }

        /** The ID of the event being registered for */
        public String eventId { get; set; }

        /** The status of the registration (e.g., Approved, Cancelled) */
        public String status { get; set; }

        /** The date and time when the registration was created */
        public DateTime createdDateTime { get; set; }

        /** The attendance status (e.g., Attended, No Show) */
        public String attendance { get; set; }

        /** Whether the contact has given email consent */
        public Boolean hasEmailConsent { get; set; }
    }

    /**
     * ArloEvent - Represents an event from Arlo
     *
     * Contains information about a training event including its code,
     * name, schedule, and status.
     */
    public class ArloEvent {
        /** The unique identifier for the event */
        public String eventId { get; set; }

        /** The event code (used for identification and matching) */
        public String code { get; set; }

        /** The name/title of the event */
        public String name { get; set; }

        /** The start date and time of the event */
        public DateTime startDateTime { get; set; }

        /** The status of the event (e.g., Active, Completed, Cancelled) */
        public String status { get; set; }
    }

    /**
     * ArloOrganisation - Represents an organisation from Arlo
     *
     * Contains information about an organisation/company in the Arlo system.
     */
    public class ArloOrganisation {
        /** The unique identifier for the organisation */
        public String organisationId { get; set; }

        /** The primary code for the organisation */
        public String codePrimary { get; set; }

        /** The name of the organisation */
        public String name { get; set; }
    }

    /**
     * ContactEventWrapper - Wrapper for contact, event, and registration data
     *
     * Used for campaign assignment operations where we need to associate
     * a contact with their event registration for creating campaign members.
     */
    public class ContactEventWrapper {
        /** The Arlo contact record */
        public ArloContact contact { get; set; }

        /** The Arlo event record */
        public ArloEvent event { get; set; }

        /** The Arlo registration linking the contact to the event */
        public ArloRegistration registration { get; set; }
    }

    /**
     * SyncResult - Tracks the results of a sync operation
     *
     * Contains statistics about the sync process including counts of
     * processed, successful, and failed records, as well as any error messages.
     */
    public class SyncResult {
        /** Total number of records processed */
        public Integer totalProcessed { get; set; }

        /** Number of records successfully processed */
        public Integer totalSuccessful { get; set; }

        /** Number of records that failed to process */
        public Integer totalFailed { get; set; }

        /** Number of new contacts created during sync */
        public Integer contactsCreated { get; set; }

        /** Number of campaign members added during sync */
        public Integer campaignMembersAdded { get; set; }

        /** List of error messages encountered during sync */
        public List<String> errors { get; set; }

        /**
         * Constructor - Initializes all counters to zero and creates empty error list
         */
        public SyncResult() {
            this.totalProcessed = 0;
            this.totalSuccessful = 0;
            this.totalFailed = 0;
            this.contactsCreated = 0;
            this.campaignMembersAdded = 0;
            this.errors = new List<String>();
        }
    }
}