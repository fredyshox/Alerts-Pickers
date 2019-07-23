import Foundation
import Contacts
import UIKit
import CoreTelephony

/// https://github.com/satishbabariya/SwiftyContacts

public struct Contacts {
    
    /// Result Enum
    ///
    /// - Success: Returns Array of Contacts
    /// - Error: Returns error
    public enum FetchResults {
        case success(response: [CNContact])
        case error(error: Error)
    }
    
    /// Result Enum
    ///
    /// - Success: Returns Contact
    /// - Error: Returns error
    public enum FetchResult {
        case success(response: CNContact)
        case error(error: Error)
    }
    
    /// Result Enum
    ///
    /// - Success: Returns Grouped By Alphabets Contacts
    /// - Error: Returns error
    public enum GroupedByAlphabetsFetchResults {
        case success(response: [String: [CNContact]])
        case error(error: Error)
    }
    
    // Fetch configuration
    public struct Configuration {
        public let excludeIds: Set<String>
        public let filter: ((CNContact) -> Bool)?
        
        public init(excludeIds: Set<String>, filter: ((CNContact) -> Bool)?) {
            self.excludeIds = excludeIds
            self.filter = filter
        }
        
        public static var `default`: Configuration {
            return Configuration(excludeIds: Set(), filter: nil)
        }
    }
    
    private let configuration: Configuration
    private let contactStore: CNContactStore
    private let defaultKeysToFetch: [CNKeyDescriptor] = [
        CNContactVCardSerialization.descriptorForRequiredKeys(),
        CNContactThumbnailImageDataKey as CNKeyDescriptor
    ]
    
    init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.contactStore = CNContactStore()
    }
    
    /// Requests access to the user's contacts
    ///
    /// - Parameter requestGranted: Result as Bool
    public func requestAccess(_ requestGranted: @escaping (Bool, Error?) -> ()) {
        contactStore.requestAccess(for: .contacts) { grandted, error in
            requestGranted(grandted, error)
        }
    }
    
    /// Returns the current authorization status to access the contact data.
    ///
    /// - Parameter requestStatus: Result as CNAuthorizationStatus
    public func authorizationStatus(_ requestStatus: @escaping (CNAuthorizationStatus) -> ()) {
        requestStatus(CNContactStore.authorizationStatus(for: .contacts))
    }
    
    // MARK: - Fetch Contacts -
    
    /// Checks if contact should be added to fetch results
    /// - Parameters:
    ///    - contact: evaluated contact
    private func isIncluded(contact: CNContact) -> Bool {
        guard !configuration.excludeIds.contains(contact.identifier) else {
            return false
        }
        
        let filtered = configuration.filter?(contact)
        return filtered ?? true
    }
    
    /// Fetching Contacts from phone with specific sort order.
    ///
    /// - Parameters:
    ///   - sortOrder: To return contacts in a specific sort order.
    ///   - completionHandler: Result Handler
    @available(iOS 10.0, *)
    public func fetchContacts(ContactsSortorder sortOrder: CNContactSortOrder = .none, completionHandler: @escaping (_ result: FetchResults) -> ()) {
        
        DispatchQueue.global(qos: .userInitiated).async {
            var contacts: [CNContact] = [CNContact]()
            let fetchRequest: CNContactFetchRequest = CNContactFetchRequest(keysToFetch: self.defaultKeysToFetch)
            fetchRequest.mutableObjects = false
            fetchRequest.unifyResults = true
            fetchRequest.sortOrder = sortOrder
            do {
                try self.contactStore.enumerateContacts(with: fetchRequest, usingBlock: {
                    contact, _ in
                    guard self.isIncluded(contact: contact) else { return }
                    
                    contacts.append(contact)
                })
                DispatchQueue.main.async {
                    completionHandler(FetchResults.success(response: contacts))
                }
            } catch {
                DispatchQueue.main.async {
                    completionHandler(FetchResults.error(error: error))
                }
            }
        }
    }
    
    /// Fetching Contacts from phone with Grouped By Alphabet
    ///
    /// - Parameter completionHandler: It will return Dictonary of Alphabets with Their Sorted Respective Contacts.
     @available(iOS 10.0, *)
     public func fetchContactsGroupedByAlphabets(completionHandler: @escaping (GroupedByAlphabetsFetchResults) -> ()) {
        let fetchRequest: CNContactFetchRequest = CNContactFetchRequest(keysToFetch: self.defaultKeysToFetch)
        var orderedContacts: [String: [CNContact]] = [String: [CNContact]]()
        CNContact.localizedString(forKey: CNLabelPhoneNumberiPhone)
        fetchRequest.mutableObjects = false
        fetchRequest.unifyResults = true
        fetchRequest.sortOrder = .givenName
        do {
            try self.contactStore.enumerateContacts(with: fetchRequest, usingBlock: { (contact, _) -> Void in
                guard self.isIncluded(contact: contact) else { return }
                // Ordering contacts based on alphabets in firstname
                var key: String = "#"
                // If ordering has to be happening via family name change it here.
                let firstLetter = contact.givenName.count > 1 ? contact.givenName[0..<1] : "?"
                if firstLetter.containsAlphabets {
                    key = firstLetter.uppercased()
                }
                var contacts: [CNContact] = orderedContacts[key] ?? []
                contacts.append(contact)
                orderedContacts[key] = contacts
            })
            completionHandler(GroupedByAlphabetsFetchResults.success(response: orderedContacts))
        } catch {
            completionHandler(GroupedByAlphabetsFetchResults.error(error: error))
        }
     }
    
    // MARK: - Search Contacts -
    
    /// Search Contact from phone
    /// - parameter string: Search String.
    /// - parameter completionHandler: Returns Either [CNContact] or Error.
    public func searchContact(searchString string: String, completionHandler: @escaping (_ result: FetchResults) -> ()) {
        
        DispatchQueue.global(qos: .userInitiated).async {
            var contacts: [CNContact] = [CNContact]()
            let predicate: NSPredicate
            if string.endIndex.utf16Offset(in: string) > 0 {
                predicate = CNContact.predicateForContacts(matchingName: string)
            } else {
                predicate = CNContact.predicateForContactsInContainer(withIdentifier: self.contactStore.defaultContainerIdentifier())
            }
            
            do {
                contacts = try self.contactStore.unifiedContacts(matching: predicate, keysToFetch: self.defaultKeysToFetch)
                let processed = contacts
                    .filter(self.isIncluded(contact:))
                    .sorted { $0.givenName < $1.givenName }
                
                DispatchQueue.main.async {
                    completionHandler(FetchResults.success(response: processed))
                }
            } catch {
                DispatchQueue.main.async {
                    completionHandler(FetchResults.error(error: error))
                }
            }
        }
    }
    
}


public struct Telephone {
    
    // PRAGMA MARK: - CoreTelephonyCheck
    
    /// Check if iOS Device supports phone calls
    /// - parameter completionHandler: Returns Bool.
    public static func isCapableToCall(completionHandler: @escaping (_ result: Bool) -> ()) {
        if UIApplication.shared.canOpenURL(NSURL(string: "tel://")! as URL) {
            // Check if iOS Device supports phone calls
            // User will get an alert error when they will try to make a phone call in airplane mode
            if let mnc: String = CTTelephonyNetworkInfo().subscriberCellularProvider?.mobileNetworkCode, !mnc.isEmpty {
                // iOS Device is capable for making calls
                completionHandler(true)
            } else {
                // Device cannot place a call at this time. SIM might be removed
                completionHandler(false)
            }
        } else {
            // iOS Device is not capable for making calls
            completionHandler(false)
        }
        
    }
    
    /// Check if iOS Device supports sms
    /// - parameter completionHandler: Returns Bool.
    public static func isCapableToSMS(completionHandler: @escaping (_ result: Bool) -> ()) {
        if UIApplication.shared.canOpenURL(NSURL(string: "sms:")! as URL) {
            completionHandler(true)
        } else {
            completionHandler(false)
        }
        
    }
    
    /// Convert CNPhoneNumber To digits
    /// - parameter CNPhoneNumber: Phone number.
    public static func CNPhoneNumberToString(CNPhoneNumber: CNPhoneNumber) -> String {
        if let result: String = CNPhoneNumber.value(forKey: "digits") as? String {
            return result
        }
        return ""
    }
    
    /// Make call to given number.
    /// - parameter CNPhoneNumber: Phone number.
    public static func makeCall(CNPhoneNumber: CNPhoneNumber) {
        if let phoneNumber: String = CNPhoneNumber.value(forKey: "digits") as? String {
            guard let url: URL = URL(string: "tel://" + "\(phoneNumber)") else {
                print("Error in Making Call")
                return
            }
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(url, options: convertToUIApplicationOpenExternalURLOptionsKeyDictionary([:]), completionHandler: nil)
            } else {
                // Fallback on earlier versions
                UIApplication.shared.openURL(url)
            }
        }
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToUIApplicationOpenExternalURLOptionsKeyDictionary(_ input: [String: Any]) -> [UIApplication.OpenExternalURLOptionsKey: Any] {
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (UIApplication.OpenExternalURLOptionsKey(rawValue: key), value)})
}
