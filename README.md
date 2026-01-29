# Life Education Trust - Arlo Integration

This repository contains the complete Arlo Integration implementation for Salesforce, including contact synchronization, event registration sync, and campaign management.

## Overview

The Arlo Integration system synchronizes contact data from Arlo to Salesforce, processes event registrations, and automatically assigns contacts to campaigns based on event participation and email consent.

## Key Features

- **Contact Synchronization**: Syncs contacts from Arlo to Salesforce with Account matching
- **Event Registration Sync**: Processes event registrations and assigns contacts to campaigns
- **Email Consent Management**: Checks and respects email consent preferences
- **Batch Processing**: Supports both Queueable and Batch class implementations
- **Deferred Processing**: Handles callout limits gracefully with deferred contact processing

## Components

### Core Classes

- **ArloContactSync.cls**: Main contact synchronization class
- **ArloEventRegistrationSync.cls**: Event registration sync (V1 - Queueable)
- **ArloEventRegistrationSyncBatchV2.cls**: Event registration sync (V2 - Batch class)
- **ArloContactRegistrationSyncQueueable.cls**: Queueable class for batch processing
- **ArloHttpService.cls**: HTTP service for Arlo API calls
- **ArloLogger.cls**: Logging utility

### Queueable Classes

- **ArloContactSyncQueueable.cls**: Processes contacts in batches
- **ArloContactRegistrationSyncQueueable.cls**: Processes contact registrations
- **ArloEventRegistrationSyncQueueable.cls**: Processes event registrations
- **ArloSyncInitialQueueable.cls**: Initial sync queueable
- **ArloEventRegistrationSyncInitialQueueable.cls**: Initial event sync queueable

### Scheduled Classes

- **ArloEventRegistrationSyncScheduled.cls**: Scheduled job for regular sync

## Documentation

- **ARLO_INTEGRATION_COMPLETE_SUMMARY.md**: Complete overview of the integration
- **ARLO_SYNC_SYSTEM_SUMMARY.md**: Quick reference for all components
- **ARLO_CONTACT_SYNC_DOCUMENTATION.md**: Contact sync documentation
- **ARLO_EVENT_REGISTRATION_SYNC_DOCUMENTATION.md**: Event registration sync documentation
- **ENDPOINTS_DOCUMENTATION.md**: API endpoints documentation
- **ARLO_SETUP_INSTRUCTIONS.md**: Setup and configuration guide
- **ARLO_MANUAL_TESTING_GUIDE.md**: Manual testing procedures

## Usage

### V1 - Queueable Implementation
```apex
ArloEventRegistrationSync.syncContactsFromEvents(null, null);
```

### V2 - Batch Implementation (Recommended)
```apex
ArloEventRegistrationSyncBatchV2.startSync(null, null);
```

## Requirements

- Salesforce Org with API access
- Arlo API credentials (configured in Custom Settings: `Arlo_Credentials__c`)
- Custom fields on Contact: `Arlo_Contact_UUID__c`
- Campaigns: `NHM - Anxiety`, `NHM - Digital wellbeing`, `NHM - Self-care`, `NHM - Neurodiversity`

## Version History

- **V2 (Batch)**: Batch class implementation with deferred processing for better callout limit handling
- **V1 (Queueable)**: Original Queueable implementation

## License

Proprietary - Life Education Trust
