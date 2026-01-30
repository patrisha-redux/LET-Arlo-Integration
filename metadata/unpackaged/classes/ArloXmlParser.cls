/**
 * ArloXmlParser - Handles all XML parsing for Arlo API responses
 *
 * This class provides methods to parse various XML responses from the Arlo API,
 * including contacts, registrations, events, organisations, and custom fields.
 * Uses a combination of regex patterns and DOM parsing for robust XML handling.
 *
 * @author Life Education
 * @date 2026
 */
public with sharing class ArloXmlParser {

    /**
     * Parse a contacts collection response from /resources/contacts/
     * Extracts ContactID, UniqueIdentifier, FirstName, LastName, Email, Phone, Status
     *
     * @param xmlBody The XML response body from the Arlo API
     * @return List of ArloModels.ArloContact objects parsed from the XML
     */
    public static List<ArloModels.ArloContact> parseContactsCollection(String xmlBody) {
        List<ArloModels.ArloContact> contacts = new List<ArloModels.ArloContact>();

        if (String.isBlank(xmlBody)) {
            return contacts;
        }

        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            Dom.XmlNode root = doc.getRootElement();

            // Find all Contact elements recursively
            findAndParseContactNodes(root, contacts);

        } catch (Exception e) {
            System.debug('ArloXmlParser.parseContactsCollection: Error parsing XML: ' + e.getMessage());
            System.debug('ArloXmlParser.parseContactsCollection: Stack trace: ' + e.getStackTraceString());
        }

        return contacts;
    }

    /**
     * Parse a registrations collection response from /resources/registrations/
     * Extracts RegistrationID, UniqueIdentifier, Status, CreatedDateTime, Attendance
     * Also extracts linked Event ID and Contact ID from Link elements
     *
     * @param xmlBody The XML response body from the Arlo API
     * @return List of ArloModels.ArloRegistration objects parsed from the XML
     */
    public static List<ArloModels.ArloRegistration> parseRegistrationsCollection(String xmlBody) {
        List<ArloModels.ArloRegistration> registrations = new List<ArloModels.ArloRegistration>();

        if (String.isBlank(xmlBody)) {
            return registrations;
        }

        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            Dom.XmlNode root = doc.getRootElement();

            // Find all Registration elements recursively
            findAndParseRegistrationNodes(root, registrations);

        } catch (Exception e) {
            System.debug('ArloXmlParser.parseRegistrationsCollection: Error parsing XML: ' + e.getMessage());
            System.debug('ArloXmlParser.parseRegistrationsCollection: Stack trace: ' + e.getStackTraceString());
        }

        return registrations;
    }

    /**
     * Parse a single event XML response
     * Extracts EventID, Code, Name (from Description), StartDateTime, Status
     *
     * @param xmlBody The XML response body from the Arlo API
     * @return ArloModels.ArloEvent object parsed from the XML, or null if parsing fails
     */
    public static ArloModels.ArloEvent parseEventDetails(String xmlBody) {
        if (String.isBlank(xmlBody)) {
            return null;
        }

        ArloModels.ArloEvent event = new ArloModels.ArloEvent();

        try {
            // Extract EventID using regex
            Pattern eventIdPattern = Pattern.compile('<EventID>([^<]+)</EventID>');
            Matcher eventIdMatcher = eventIdPattern.matcher(xmlBody);
            if (eventIdMatcher.find()) {
                event.eventId = eventIdMatcher.group(1).trim();
            }

            // Extract Code using regex
            Pattern codePattern = Pattern.compile('<Code>([^<]+)</Code>');
            Matcher codeMatcher = codePattern.matcher(xmlBody);
            if (codeMatcher.find()) {
                event.code = codeMatcher.group(1).trim();
            }

            // Extract Name from Description element
            Pattern descPattern = Pattern.compile('<Description>([^<]+)</Description>');
            Matcher descMatcher = descPattern.matcher(xmlBody);
            if (descMatcher.find()) {
                event.name = descMatcher.group(1).trim();
            }

            // Try Name element as fallback if Description not found
            if (String.isBlank(event.name)) {
                Pattern namePattern = Pattern.compile('<Name>([^<]+)</Name>');
                Matcher nameMatcher = namePattern.matcher(xmlBody);
                if (nameMatcher.find()) {
                    event.name = nameMatcher.group(1).trim();
                }
            }

            // Extract StartDateTime using regex
            Pattern startPattern = Pattern.compile('<StartDateTime>([^<]+)</StartDateTime>');
            Matcher startMatcher = startPattern.matcher(xmlBody);
            if (startMatcher.find()) {
                String dateTimeStr = startMatcher.group(1).trim();
                event.startDateTime = parseDateTime(dateTimeStr);
            }

            // Extract Status using regex
            Pattern statusPattern = Pattern.compile('<Status>([^<]+)</Status>');
            Matcher statusMatcher = statusPattern.matcher(xmlBody);
            if (statusMatcher.find()) {
                event.status = statusMatcher.group(1).trim();
            }

            // Try to extract EventID from self link if not found
            if (String.isBlank(event.eventId)) {
                String selfLink = extractLinkHref(xmlBody, 'self');
                if (String.isNotBlank(selfLink)) {
                    Pattern idPattern = Pattern.compile('/events/(\\d+)/');
                    Matcher idMatcher = idPattern.matcher(selfLink);
                    if (idMatcher.find()) {
                        event.eventId = idMatcher.group(1);
                    }
                }
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.parseEventDetails: Error parsing XML: ' + e.getMessage());
            return null;
        }

        // Return null if no event data was found
        if (String.isBlank(event.eventId) && String.isBlank(event.code) && String.isBlank(event.name)) {
            return null;
        }

        return event;
    }

    /**
     * Parse a single contact XML response with full details
     * Extracts all fields including employment link
     *
     * @param xmlBody The XML response body from the Arlo API
     * @return ArloModels.ArloContact object parsed from the XML, or null if parsing fails
     */
    public static ArloModels.ArloContact parseContactDetails(String xmlBody) {
        if (String.isBlank(xmlBody)) {
            return null;
        }

        ArloModels.ArloContact contact = new ArloModels.ArloContact();

        try {
            // Extract UniqueIdentifier (UUID)
            Pattern uuidPattern = Pattern.compile('<UniqueIdentifier>([^<]+)</UniqueIdentifier>');
            Matcher uuidMatcher = uuidPattern.matcher(xmlBody);
            if (uuidMatcher.find()) {
                contact.contactId = uuidMatcher.group(1).trim();
            }

            // Extract ContactID (numeric ID)
            Pattern contactIdPattern = Pattern.compile('<ContactID>([^<]+)</ContactID>');
            Matcher contactIdMatcher = contactIdPattern.matcher(xmlBody);
            if (contactIdMatcher.find()) {
                contact.numericContactId = contactIdMatcher.group(1).trim();
                // Use as backup UUID if UniqueIdentifier not found
                if (String.isBlank(contact.contactId)) {
                    contact.contactId = contact.numericContactId;
                }
            }

            // Extract FirstName
            Pattern firstNamePattern = Pattern.compile('<FirstName>([^<]+)</FirstName>');
            Matcher firstNameMatcher = firstNamePattern.matcher(xmlBody);
            if (firstNameMatcher.find()) {
                contact.firstName = firstNameMatcher.group(1).trim();
            }

            // Extract LastName
            Pattern lastNamePattern = Pattern.compile('<LastName>([^<]+)</LastName>');
            Matcher lastNameMatcher = lastNamePattern.matcher(xmlBody);
            if (lastNameMatcher.find()) {
                contact.lastName = lastNameMatcher.group(1).trim();
            }

            // Extract Email
            Pattern emailPattern = Pattern.compile('<Email>([^<]+)</Email>');
            Matcher emailMatcher = emailPattern.matcher(xmlBody);
            if (emailMatcher.find()) {
                contact.email = emailMatcher.group(1).trim();
            }

            // Extract Phone (multiple possible field names)
            Pattern phonePattern = Pattern.compile('<PhoneWork>([^<]+)</PhoneWork>');
            Matcher phoneMatcher = phonePattern.matcher(xmlBody);
            if (phoneMatcher.find()) {
                contact.phone = phoneMatcher.group(1).trim();
            } else {
                // Try PhoneMobile as fallback
                Pattern phoneMobilePattern = Pattern.compile('<PhoneMobile>([^<]+)</PhoneMobile>');
                Matcher phoneMobileMatcher = phoneMobilePattern.matcher(xmlBody);
                if (phoneMobileMatcher.find()) {
                    contact.phone = phoneMobileMatcher.group(1).trim();
                } else {
                    // Try PhoneNumber as final fallback
                    Pattern phoneAltPattern = Pattern.compile('<PhoneNumber>([^<]+)</PhoneNumber>');
                    Matcher phoneAltMatcher = phoneAltPattern.matcher(xmlBody);
                    if (phoneAltMatcher.find()) {
                        contact.phone = phoneAltMatcher.group(1).trim();
                    }
                }
            }

            // Extract JobTitle
            Pattern jobTitlePattern = Pattern.compile('<JobTitle>([^<]+)</JobTitle>');
            Matcher jobTitleMatcher = jobTitlePattern.matcher(xmlBody);
            if (jobTitleMatcher.find()) {
                contact.title = jobTitleMatcher.group(1).trim();
            }

            // Extract Status
            Pattern statusPattern = Pattern.compile('<Status>([^<]+)</Status>');
            Matcher statusMatcher = statusPattern.matcher(xmlBody);
            if (statusMatcher.find()) {
                contact.status = statusMatcher.group(1).trim();
            }

            // Extract organisation ID from employment link
            String employmentLink = extractLinkHref(xmlBody, 'employment');
            if (String.isNotBlank(employmentLink)) {
                // Will need to follow this link to get organisation details
                System.debug('ArloXmlParser.parseContactDetails: Found employment link: ' + employmentLink);
            }

            // Try to extract numeric contact ID from self link if not found
            if (String.isBlank(contact.numericContactId)) {
                String selfLink = extractLinkHref(xmlBody, 'self');
                if (String.isNotBlank(selfLink)) {
                    Pattern idPattern = Pattern.compile('/contacts/(\\d+)/');
                    Matcher idMatcher = idPattern.matcher(selfLink);
                    if (idMatcher.find()) {
                        contact.numericContactId = idMatcher.group(1);
                    }
                }
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.parseContactDetails: Error parsing XML: ' + e.getMessage());
            return null;
        }

        // Return null if no contact data was found
        if (String.isBlank(contact.contactId) && String.isBlank(contact.firstName) &&
            String.isBlank(contact.lastName) && String.isBlank(contact.email)) {
            return null;
        }

        return contact;
    }

    /**
     * Parse organisation XML to get CodePrimary (the Account Number)
     *
     * @param xmlBody The XML response body from the Arlo API
     * @return ArloModels.ArloOrganisation object parsed from the XML, or null if parsing fails
     */
    public static ArloModels.ArloOrganisation parseOrganisationDetails(String xmlBody) {
        if (String.isBlank(xmlBody)) {
            return null;
        }

        ArloModels.ArloOrganisation org = new ArloModels.ArloOrganisation();

        try {
            // Try DOM parsing first (more robust)
            try {
                Dom.Document doc = new Dom.Document();
                doc.load(xmlBody);
                Dom.XmlNode root = doc.getRootElement();

                // Search for CodePrimary node recursively
                Dom.XmlNode codePrimaryNode = findNodeByName(root, 'CodePrimary');
                if (codePrimaryNode != null) {
                    org.codePrimary = codePrimaryNode.getText().trim();
                }

                // Search for OrganisationID node
                Dom.XmlNode orgIdNode = findNodeByName(root, 'OrganisationID');
                if (orgIdNode != null) {
                    org.organisationId = orgIdNode.getText().trim();
                }

                // Search for Name node
                Dom.XmlNode nameNode = findNodeByName(root, 'Name');
                if (nameNode != null) {
                    org.name = nameNode.getText().trim();
                }

            } catch (Exception domEx) {
                System.debug('ArloXmlParser.parseOrganisationDetails: DOM parsing failed, trying regex: ' + domEx.getMessage());
            }

            // Fallback to regex if DOM didn't find CodePrimary
            if (String.isBlank(org.codePrimary)) {
                Pattern codePrimaryPattern = Pattern.compile('(?i)<CodePrimary[^>]*>(.*?)</CodePrimary>');
                Matcher matcher = codePrimaryPattern.matcher(xmlBody);
                if (matcher.find()) {
                    org.codePrimary = matcher.group(1).trim();
                }
            }

            // Fallback regex for OrganisationID
            if (String.isBlank(org.organisationId)) {
                Pattern orgIdPattern = Pattern.compile('<OrganisationID>([^<]+)</OrganisationID>');
                Matcher orgIdMatcher = orgIdPattern.matcher(xmlBody);
                if (orgIdMatcher.find()) {
                    org.organisationId = orgIdMatcher.group(1).trim();
                }
            }

            // Try to extract organisation ID from self link if not found
            if (String.isBlank(org.organisationId)) {
                String selfLink = extractLinkHref(xmlBody, 'self');
                if (String.isNotBlank(selfLink)) {
                    Pattern idPattern = Pattern.compile('/organisations/(\\d+)/?');
                    Matcher idMatcher = idPattern.matcher(selfLink);
                    if (idMatcher.find()) {
                        org.organisationId = idMatcher.group(1);
                    }
                }
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.parseOrganisationDetails: Error parsing XML: ' + e.getMessage());
            return null;
        }

        // Return null if no organisation data was found
        if (String.isBlank(org.organisationId) && String.isBlank(org.codePrimary)) {
            return null;
        }

        return org;
    }

    /**
     * Parse custom fields XML to check for email consent field
     *
     * @param xmlBody The XML response body from the Arlo API
     * @return Map of field name to field value
     */
    public static Map<String, String> parseCustomFields(String xmlBody) {
        Map<String, String> customFields = new Map<String, String>();

        if (String.isBlank(xmlBody)) {
            return customFields;
        }

        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            Dom.XmlNode root = doc.getRootElement();

            // Find all CustomField elements recursively
            findAndParseCustomFieldNodes(root, customFields);

        } catch (Exception e) {
            System.debug('ArloXmlParser.parseCustomFields: Error parsing XML: ' + e.getMessage());
            System.debug('ArloXmlParser.parseCustomFields: Stack trace: ' + e.getStackTraceString());

            // Fallback to regex for common custom field patterns
            try {
                String normalizedXml = xmlBody.replaceAll('\\s+', ' ');

                // Pattern for Arlo format: <Field><Name>fieldname</Name><Value><Boolean>true</Boolean></Value></Field>
                Pattern arloFieldPattern = Pattern.compile('<Field[^>]*>.*?<Name>([^<]+)</Name>.*?<Value>.*?<(Boolean|String|Integer|Decimal|DateTime|Date)>([^<]*)</\\2>.*?</Value>.*?</Field>');
                Matcher arloMatcher = arloFieldPattern.matcher(normalizedXml);
                while (arloMatcher.find()) {
                    String fieldName = arloMatcher.group(1).trim();
                    String fieldValue = arloMatcher.group(3).trim();
                    customFields.put(fieldName, fieldValue);
                }

                // Pattern for simple format: <Field><Name>fieldname</Name><Value>value</Value></Field>
                Pattern simpleFieldPattern = Pattern.compile('<Field[^>]*>.*?<Name>([^<]+)</Name>.*?<Value>([^<]*)</Value>.*?</Field>');
                Matcher simpleMatcher = simpleFieldPattern.matcher(normalizedXml);
                while (simpleMatcher.find()) {
                    String fieldName = simpleMatcher.group(1).trim();
                    String fieldValue = simpleMatcher.group(2).trim();
                    if (!customFields.containsKey(fieldName)) {
                        customFields.put(fieldName, fieldValue);
                    }
                }

                // Pattern for CustomField format: <CustomField><FieldName>name</FieldName><Value>value</Value></CustomField>
                Pattern customFieldPattern = Pattern.compile('<CustomField[^>]*>.*?<FieldName>([^<]+)</FieldName>.*?<Value>([^<]*)</Value>.*?</CustomField>');
                Matcher customMatcher = customFieldPattern.matcher(normalizedXml);
                while (customMatcher.find()) {
                    String fieldName = customMatcher.group(1).trim();
                    String fieldValue = customMatcher.group(2).trim();
                    if (!customFields.containsKey(fieldName)) {
                        customFields.put(fieldName, fieldValue);
                    }
                }
            } catch (Exception regexEx) {
                System.debug('ArloXmlParser.parseCustomFields: Regex fallback also failed: ' + regexEx.getMessage());
            }
        }

        return customFields;
    }

    /**
     * Extract the next page URL from pagination Link element
     *
     * @param xmlBody The XML response body from the Arlo API
     * @return The href of the next link, or null if not found
     */
    public static String extractNextLink(String xmlBody) {
        if (String.isBlank(xmlBody)) {
            return null;
        }

        try {
            // Try DOM parsing first
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            Dom.XmlNode root = doc.getRootElement();

            String nextLink = findNextLinkRecursive(root);
            if (String.isNotBlank(nextLink)) {
                return nextLink;
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.extractNextLink: DOM parsing failed, trying regex: ' + e.getMessage());
        }

        // Fallback to regex
        try {
            Pattern nextPattern = Pattern.compile('<Link[^>]*rel="next"[^>]*href="([^"]*)"');
            Matcher nextMatcher = nextPattern.matcher(xmlBody);
            if (nextMatcher.find()) {
                return nextMatcher.group(1);
            }

            // Try alternative pattern (href before rel)
            Pattern altPattern = Pattern.compile('<Link[^>]*href="([^"]*)"[^>]*rel="next"');
            Matcher altMatcher = altPattern.matcher(xmlBody);
            if (altMatcher.find()) {
                return altMatcher.group(1);
            }
        } catch (Exception e) {
            System.debug('ArloXmlParser.extractNextLink: Regex also failed: ' + e.getMessage());
        }

        return null;
    }

    /**
     * Extract href from a Link element where rel contains the given string
     *
     * @param xmlBody The XML response body from the Arlo API
     * @param relContains The string that should be contained in the rel attribute
     * @return The href of the matching link, or null if not found
     */
    public static String extractLinkHref(String xmlBody, String relContains) {
        if (String.isBlank(xmlBody) || String.isBlank(relContains)) {
            return null;
        }

        try {
            // Try DOM parsing first
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            Dom.XmlNode root = doc.getRootElement();

            String href = findLinkHrefRecursive(root, relContains);
            if (String.isNotBlank(href)) {
                return href;
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.extractLinkHref: DOM parsing failed, trying regex: ' + e.getMessage());
        }

        // Fallback to regex
        try {
            // Pattern 1: rel before href
            Pattern pattern1 = Pattern.compile('<Link[^>]*rel="[^"]*' + Pattern.quote(relContains) + '[^"]*"[^>]*href="([^"]*)"');
            Matcher matcher1 = pattern1.matcher(xmlBody);
            if (matcher1.find()) {
                return matcher1.group(1);
            }

            // Pattern 2: href before rel
            Pattern pattern2 = Pattern.compile('<Link[^>]*href="([^"]*)"[^>]*rel="[^"]*' + Pattern.quote(relContains) + '[^"]*"');
            Matcher matcher2 = pattern2.matcher(xmlBody);
            if (matcher2.find()) {
                return matcher2.group(1);
            }
        } catch (Exception e) {
            System.debug('ArloXmlParser.extractLinkHref: Regex also failed: ' + e.getMessage());
        }

        return null;
    }

    /**
     * Extract a simple text element value from XML using the element name
     * Useful for extracting single values like Status, Code, Name, etc.
     *
     * @param xmlBody The XML response body
     * @param elementName The name of the element to extract (e.g., 'Status', 'Code')
     * @return The text value of the element, or null if not found
     */
    public static String extractElementValue(String xmlBody, String elementName) {
        if (String.isBlank(xmlBody) || String.isBlank(elementName)) {
            return null;
        }

        try {
            // Try DOM parsing first
            Dom.Document doc = new Dom.Document();
            doc.load(xmlBody);
            Dom.XmlNode root = doc.getRootElement();

            Dom.XmlNode targetNode = findNodeByName(root, elementName);
            if (targetNode != null) {
                String text = targetNode.getText();
                return String.isNotBlank(text) ? text.trim() : null;
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.extractElementValue: DOM parsing failed, trying regex: ' + e.getMessage());
        }

        // Fallback to regex
        try {
            Pattern pattern = Pattern.compile('<' + Pattern.quote(elementName) + '>([^<]+)</' + Pattern.quote(elementName) + '>');
            Matcher matcher = pattern.matcher(xmlBody);
            if (matcher.find()) {
                return matcher.group(1).trim();
            }
        } catch (Exception e) {
            System.debug('ArloXmlParser.extractElementValue: Regex also failed: ' + e.getMessage());
        }

        return null;
    }

    /**
     * Extract an ID from a link URL using a pattern
     * For example, extract "123" from "/resources/contacts/123/"
     *
     * @param url The URL to extract from
     * @param resourceType The resource type (e.g., 'contacts', 'events', 'registrations')
     * @return The extracted ID, or null if not found
     */
    public static String extractIdFromUrl(String url, String resourceType) {
        if (String.isBlank(url) || String.isBlank(resourceType)) {
            return null;
        }

        try {
            Pattern pattern = Pattern.compile('/' + Pattern.quote(resourceType) + '/(\\d+)/?');
            Matcher matcher = pattern.matcher(url);
            if (matcher.find()) {
                return matcher.group(1);
            }
        } catch (Exception e) {
            System.debug('ArloXmlParser.extractIdFromUrl: Error: ' + e.getMessage());
        }

        return null;
    }

    /**
     * Extract IDs from all links matching a resource type
     * For example, extract all registration IDs from a contact's registrations response
     *
     * @param xmlBody The XML response body
     * @param resourceType The resource type (e.g., 'registrations', 'events')
     * @return Set of extracted IDs
     */
    public static Set<String> extractResourceIds(String xmlBody, String resourceType) {
        Set<String> ids = new Set<String>();

        if (String.isBlank(xmlBody) || String.isBlank(resourceType)) {
            return ids;
        }

        try {
            // Method 1: Look for Resource elements with type containing the resource type
            Pattern resourcePattern = Pattern.compile('<Resource[^>]*type="[^"]*' + Pattern.quote(resourceType) + '[^"]*"[^>]*>');
            Matcher resourceMatcher = resourcePattern.matcher(xmlBody);
            while (resourceMatcher.find()) {
                Integer resourceStart = resourceMatcher.start();
                Integer searchEnd = Math.min(resourceStart + 500, xmlBody.length());
                String resourceSection = xmlBody.substring(resourceStart, searchEnd);
                Pattern linkPattern = Pattern.compile('<Link[^>]*rel="self"[^>]*href="[^"]*/' + Pattern.quote(resourceType) + '/(\\d+)/"');
                Matcher linkMatcher = linkPattern.matcher(resourceSection);
                if (linkMatcher.find()) {
                    ids.add(linkMatcher.group(1));
                }
            }

            // Method 2: Self links if no resources found
            if (ids.isEmpty()) {
                Pattern selfLinkPattern = Pattern.compile('<Link[^>]*rel="self"[^>]*href="[^"]*/' + Pattern.quote(resourceType) + '/(\\d+)/"');
                Matcher selfMatcher = selfLinkPattern.matcher(xmlBody);
                while (selfMatcher.find()) {
                    ids.add(selfMatcher.group(1));
                }
            }

            // Method 3: Fallback - any link containing the resource type
            if (ids.isEmpty()) {
                Pattern fallbackPattern = Pattern.compile('/' + Pattern.quote(resourceType) + '/(\\d+)/');
                Matcher fallbackMatcher = fallbackPattern.matcher(xmlBody);
                while (fallbackMatcher.find()) {
                    ids.add(fallbackMatcher.group(1));
                }
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.extractResourceIds: Error: ' + e.getMessage());
        }

        return ids;
    }

    /**
     * Extract links (full URLs) from XML that match a resource type pattern
     * For example, extract all registration links like "/resources/registrations/123/"
     *
     * @param xmlBody The XML response body
     * @param resourceType The resource type (e.g., 'registrations', 'events', 'contacts')
     * @return List of matching link URLs
     */
    public static List<String> extractResourceLinks(String xmlBody, String resourceType) {
        List<String> links = new List<String>();

        if (String.isBlank(xmlBody) || String.isBlank(resourceType)) {
            return links;
        }

        try {
            // Extract link hrefs that contain the resource type pattern
            Pattern linkPattern = Pattern.compile('<Link[^>]*href="([^"]*' + Pattern.quote(resourceType) + '/\\d+/)"[^>]*>');
            Matcher matcher = linkPattern.matcher(xmlBody);
            while (matcher.find()) {
                String link = matcher.group(1);
                if (!links.contains(link)) {
                    links.add(link);
                }
            }
        } catch (Exception e) {
            System.debug('ArloXmlParser.extractResourceLinks: Error: ' + e.getMessage());
        }

        return links;
    }

    /**
     * Extract the first ID from a contact search response
     * This handles the Arlo API response from /resources/contacts/?Email=... or /resources/contacts/?UniqueIdentifier=...
     *
     * @param xmlBody The XML response body from the Arlo API
     * @return The first contact ID found, or null if not found
     */
    public static String extractFirstContactIdFromSearch(String xmlBody) {
        if (String.isBlank(xmlBody)) {
            return null;
        }

        try {
            // Method 1: Look for Resource element with type="Contact" and its self link
            Pattern resourcePattern = Pattern.compile('<Resource[^>]*type="[^"]*Contact[^"]*"[^>]*>');
            Matcher resourceMatcher = resourcePattern.matcher(xmlBody);
            if (resourceMatcher.find()) {
                Integer startPos = resourceMatcher.end();
                String remaining = xmlBody.substring(startPos);
                String searchArea = remaining.length() > 1000 ? remaining.substring(0, 1000) : remaining;
                Pattern linkPattern = Pattern.compile('<Link[^>]*rel="self"[^>]*href="[^"]*/contacts/(\\d+)/"');
                Matcher linkMatcher = linkPattern.matcher(searchArea);
                if (linkMatcher.find()) {
                    return linkMatcher.group(1);
                }
            }

            // Method 2: Look for any self link pointing to contacts
            Pattern contactIdPattern = Pattern.compile('<Link[^>]*rel="self"[^>]*href="[^"]*/contacts/(\\d+)/"');
            Matcher matcher = contactIdPattern.matcher(xmlBody);
            if (matcher.find()) {
                return matcher.group(1);
            }

            // Method 3: Look for any link with href containing /contacts/
            Pattern broadPattern = Pattern.compile('href="[^"]*/contacts/(\\d+)/"');
            Matcher broadMatcher = broadPattern.matcher(xmlBody);
            if (broadMatcher.find()) {
                return broadMatcher.group(1);
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.extractFirstContactIdFromSearch: Error: ' + e.getMessage());
        }

        return null;
    }

    /**
     * Extract an ID from a link with a specific rel attribute containing a keyword
     * For example, extract event ID from a registration's Event link
     *
     * @param xmlBody The XML response body
     * @param relKeyword The keyword that should be in the rel attribute (e.g., 'Event', 'Contact')
     * @param resourceType The resource type in the URL (e.g., 'events', 'contacts')
     * @return The extracted ID, or null if not found
     */
    public static String extractIdFromLinkByRel(String xmlBody, String relKeyword, String resourceType) {
        if (String.isBlank(xmlBody) || String.isBlank(relKeyword) || String.isBlank(resourceType)) {
            return null;
        }

        try {
            // Pattern 1: rel before href
            Pattern pattern1 = Pattern.compile('<Link[^>]*rel="[^"]*' + Pattern.quote(relKeyword) + '[^"]*"[^>]*href="[^"]*/' + Pattern.quote(resourceType) + '/(\\d+)/"');
            Matcher matcher1 = pattern1.matcher(xmlBody);
            if (matcher1.find()) {
                return matcher1.group(1);
            }

            // Pattern 2: href before rel
            Pattern pattern2 = Pattern.compile('<Link[^>]*href="[^"]*/' + Pattern.quote(resourceType) + '/(\\d+)/"[^>]*rel="[^"]*' + Pattern.quote(relKeyword) + '[^"]*"');
            Matcher matcher2 = pattern2.matcher(xmlBody);
            if (matcher2.find()) {
                return matcher2.group(1);
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.extractIdFromLinkByRel: Error: ' + e.getMessage());
        }

        return null;
    }

    // ==================== Private Helper Methods ====================

    /**
     * Recursively find and parse Contact nodes from XML
     */
    private static void findAndParseContactNodes(Dom.XmlNode node, List<ArloModels.ArloContact> contacts) {
        String nodeName = node.getName();

        if (nodeName == 'Contact' || nodeName == 'entry') {
            ArloModels.ArloContact contact = parseContactNodeFromDom(node);
            if (contact != null) {
                contacts.add(contact);
            }
        }

        // Recursively check child elements
        if (node.getChildElements() != null) {
            for (Dom.XmlNode child : node.getChildElements()) {
                findAndParseContactNodes(child, contacts);
            }
        }
    }

    /**
     * Parse a single Contact node from DOM
     */
    private static ArloModels.ArloContact parseContactNodeFromDom(Dom.XmlNode node) {
        ArloModels.ArloContact contact = new ArloModels.ArloContact();

        try {
            for (Dom.XmlNode child : node.getChildElements()) {
                String childName = child.getName();
                String childValue = child.getText();

                // Handle namespaces
                if (childName != null && childName.contains(':')) {
                    childName = childName.substring(childName.indexOf(':') + 1);
                }

                // Check for Link elements to extract numeric Contact ID
                if (childName == 'Link') {
                    String href = child.getAttributeValue('href', null);
                    if (String.isNotBlank(href) && href.contains('/contacts/')) {
                        Pattern idPattern = Pattern.compile('/contacts/(\\d+)/');
                        Matcher idMatcher = idPattern.matcher(href);
                        if (idMatcher.find()) {
                            contact.numericContactId = idMatcher.group(1);
                        }
                    }
                }

                // Map field names to contact properties
                if (childName == 'UniqueIdentifier') {
                    contact.contactId = childValue;
                } else if (childName == 'ContactID' || childName == 'ContactId') {
                    if (String.isBlank(contact.numericContactId)) {
                        contact.numericContactId = childValue;
                    }
                    if (String.isBlank(contact.contactId)) {
                        contact.contactId = childValue;
                    }
                } else if (childName == 'FirstName' || childName == 'Firstname') {
                    contact.firstName = childValue;
                } else if (childName == 'LastName' || childName == 'Lastname' || childName == 'Surname') {
                    contact.lastName = childValue;
                } else if (childName == 'Email' || childName == 'EmailAddress') {
                    contact.email = childValue;
                } else if (childName == 'PhoneWork' || childName == 'PhoneNumber' || childName == 'Phone') {
                    contact.phone = childValue;
                } else if (childName == 'Status') {
                    contact.status = childValue;
                }
            }

            // Only return contact if it has meaningful data
            if (String.isNotBlank(contact.firstName) || String.isNotBlank(contact.lastName) ||
                String.isNotBlank(contact.email) || String.isNotBlank(contact.contactId)) {
                return contact;
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.parseContactNodeFromDom: Error: ' + e.getMessage());
        }

        return null;
    }

    /**
     * Recursively find and parse Registration nodes from XML
     */
    private static void findAndParseRegistrationNodes(Dom.XmlNode node, List<ArloModels.ArloRegistration> registrations) {
        String nodeName = node.getName();

        if (nodeName == 'Registration' || nodeName == 'Resource') {
            // Check if this is a Registration resource
            String resourceType = node.getAttributeValue('type', null);
            if (nodeName == 'Registration' || (resourceType != null && resourceType.contains('Registration'))) {
                ArloModels.ArloRegistration registration = parseRegistrationNodeFromDom(node);
                if (registration != null) {
                    registrations.add(registration);
                }
            }
        }

        // Recursively check child elements
        if (node.getChildElements() != null) {
            for (Dom.XmlNode child : node.getChildElements()) {
                findAndParseRegistrationNodes(child, registrations);
            }
        }
    }

    /**
     * Parse a single Registration node from DOM
     */
    private static ArloModels.ArloRegistration parseRegistrationNodeFromDom(Dom.XmlNode node) {
        ArloModels.ArloRegistration registration = new ArloModels.ArloRegistration();

        try {
            for (Dom.XmlNode child : node.getChildElements()) {
                String childName = child.getName();
                String childValue = child.getText();

                // Handle namespaces
                if (childName != null && childName.contains(':')) {
                    childName = childName.substring(childName.indexOf(':') + 1);
                }

                // Check for Link elements to extract Event ID and Contact ID
                // Arlo API returns Link elements with rel containing "Event" or "Contact"
                // and href like /resources/events/12/ or /resources/contacts/456/
                if (childName == 'Link') {
                    String href = child.getAttributeValue('href', null);
                    String rel = child.getAttributeValue('rel', null);

                    if (String.isNotBlank(href)) {
                        // Extract Event ID - check rel attribute contains "Event" OR href contains /events/
                        if ((rel != null && rel.containsIgnoreCase('Event')) || href.contains('/events/')) {
                            Pattern eventIdPattern = Pattern.compile('/events/(\\d+)/?');
                            Matcher eventIdMatcher = eventIdPattern.matcher(href);
                            if (eventIdMatcher.find()) {
                                registration.eventId = eventIdMatcher.group(1);
                            }
                        }

                        // Extract Contact ID - check rel attribute contains "Contact" OR href contains /contacts/
                        if ((rel != null && rel.containsIgnoreCase('Contact')) || href.contains('/contacts/')) {
                            Pattern contactIdPattern = Pattern.compile('/contacts/(\\d+)/?');
                            Matcher contactIdMatcher = contactIdPattern.matcher(href);
                            if (contactIdMatcher.find()) {
                                registration.contactId = contactIdMatcher.group(1);
                            }
                        }

                        // Extract Registration ID from self link
                        if ((rel != null && (rel.equals('self') || rel.containsIgnoreCase('self'))) && href.contains('/registrations/')) {
                            Pattern regIdPattern = Pattern.compile('/registrations/(\\d+)/?');
                            Matcher regIdMatcher = regIdPattern.matcher(href);
                            if (regIdMatcher.find()) {
                                registration.registrationId = regIdMatcher.group(1);
                            }
                        }
                    }
                }

                // Map field names to registration properties
                if (childName == 'RegistrationID' || childName == 'RegistrationId') {
                    registration.registrationId = childValue;
                } else if (childName == 'UniqueIdentifier') {
                    registration.uniqueIdentifier = childValue;
                } else if (childName == 'Status') {
                    registration.status = childValue;
                } else if (childName == 'CreatedDateTime') {
                    registration.createdDateTime = parseDateTime(childValue);
                } else if (childName == 'Attendance') {
                    registration.attendance = childValue;
                }
            }

            // Only return registration if it has meaningful data
            if (String.isNotBlank(registration.registrationId) || String.isNotBlank(registration.uniqueIdentifier)) {
                return registration;
            }

        } catch (Exception e) {
            System.debug('ArloXmlParser.parseRegistrationNodeFromDom: Error: ' + e.getMessage());
        }

        return null;
    }

    /**
     * Recursively find and parse CustomField nodes from XML
     * Handles Arlo format: <Field><Name>fieldname</Name><Value><Boolean>true</Boolean></Value></Field>
     * Also handles: <CustomField><FieldName>name</FieldName><Value>value</Value></CustomField>
     */
    private static void findAndParseCustomFieldNodes(Dom.XmlNode node, Map<String, String> customFields) {
        String nodeName = node.getName();

        if (nodeName == 'CustomField' || nodeName == 'CustomFieldValue' || nodeName == 'Field') {
            String fieldName = null;
            String fieldValue = null;

            for (Dom.XmlNode child : node.getChildElements()) {
                String childName = child.getName();
                if (childName == 'FieldName' || childName == 'Name') {
                    fieldName = child.getText();
                } else if (childName == 'Value' || childName == 'FieldValue') {
                    // First try to get direct text value
                    fieldValue = child.getText();

                    // If empty, check for nested type elements (Arlo format: <Value><Boolean>true</Boolean></Value>)
                    if (String.isBlank(fieldValue) && child.getChildElements() != null) {
                        for (Dom.XmlNode valueChild : child.getChildElements()) {
                            String valueChildName = valueChild.getName();
                            // Handle typed values: <Boolean>, <String>, <Integer>, <Decimal>, etc.
                            if (valueChildName == 'Boolean' || valueChildName == 'String' ||
                                valueChildName == 'Integer' || valueChildName == 'Decimal' ||
                                valueChildName == 'DateTime' || valueChildName == 'Date') {
                                fieldValue = valueChild.getText();
                                break;
                            }
                        }
                    }
                }
            }

            if (String.isNotBlank(fieldName)) {
                customFields.put(fieldName, fieldValue != null ? fieldValue : '');
            }
        }

        // Recursively check child elements
        if (node.getChildElements() != null) {
            for (Dom.XmlNode child : node.getChildElements()) {
                findAndParseCustomFieldNodes(child, customFields);
            }
        }
    }

    /**
     * Recursively find Link element with rel="next"
     */
    private static String findNextLinkRecursive(Dom.XmlNode node) {
        if (node.getName() == 'Link') {
            String rel = node.getAttributeValue('rel', null);
            if (rel != null && rel.equals('next')) {
                return node.getAttributeValue('href', null);
            }
        }

        if (node.getChildElements() != null) {
            for (Dom.XmlNode child : node.getChildElements()) {
                String nextLink = findNextLinkRecursive(child);
                if (String.isNotBlank(nextLink)) {
                    return nextLink;
                }
            }
        }

        return null;
    }

    /**
     * Recursively find Link element where rel contains the given string
     */
    private static String findLinkHrefRecursive(Dom.XmlNode node, String relContains) {
        if (node.getName() == 'Link') {
            String rel = node.getAttributeValue('rel', null);
            if (rel != null && rel.containsIgnoreCase(relContains)) {
                return node.getAttributeValue('href', null);
            }
        }

        if (node.getChildElements() != null) {
            for (Dom.XmlNode child : node.getChildElements()) {
                String href = findLinkHrefRecursive(child, relContains);
                if (String.isNotBlank(href)) {
                    return href;
                }
            }
        }

        return null;
    }

    /**
     * Find XML node by name (handles namespaces)
     */
    private static Dom.XmlNode findNodeByName(Dom.XmlNode parent, String nodeName) {
        if (parent == null) {
            return null;
        }

        String localName = parent.getName();
        if (localName != null && localName.equalsIgnoreCase(nodeName)) {
            return parent;
        }

        if (parent.getChildElements() != null) {
            for (Dom.XmlNode child : parent.getChildElements()) {
                Dom.XmlNode found = findNodeByName(child, nodeName);
                if (found != null) {
                    return found;
                }
            }
        }

        return null;
    }

    /**
     * Parse ISO 8601 datetime string to DateTime
     */
    private static DateTime parseDateTime(String dateTimeStr) {
        if (String.isBlank(dateTimeStr)) {
            return null;
        }

        try {
            // Handle various ISO 8601 formats
            // Format: 2024-01-15T10:30:00Z or 2024-01-15T10:30:00+12:00
            String cleanedStr = dateTimeStr.trim();

            // Remove timezone info for parsing
            if (cleanedStr.endsWith('Z')) {
                cleanedStr = cleanedStr.substring(0, cleanedStr.length() - 1);
            } else if (cleanedStr.contains('+')) {
                cleanedStr = cleanedStr.substring(0, cleanedStr.indexOf('+'));
            } else if (cleanedStr.lastIndexOf('-') > 10) {
                // Handle negative timezone offset
                cleanedStr = cleanedStr.substring(0, cleanedStr.lastIndexOf('-'));
            }

            // Parse the datetime
            return DateTime.valueOf(cleanedStr.replace('T', ' '));

        } catch (Exception e) {
            System.debug('ArloXmlParser.parseDateTime: Error parsing datetime "' + dateTimeStr + '": ' + e.getMessage());
            return null;
        }
    }
}