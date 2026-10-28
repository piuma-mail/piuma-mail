import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('pt'),
  ];

  /// Button that switches to the light theme
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Button that switches to the dark theme
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @catalogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Component catalog · Phase 0'**
  String get catalogSubtitle;

  /// No description provided for @sectionColors.
  ///
  /// In en, this message translates to:
  /// **'Colors'**
  String get sectionColors;

  /// No description provided for @sectionTypography.
  ///
  /// In en, this message translates to:
  /// **'Typography'**
  String get sectionTypography;

  /// No description provided for @sectionButtons.
  ///
  /// In en, this message translates to:
  /// **'Buttons'**
  String get sectionButtons;

  /// No description provided for @sectionFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get sectionFilters;

  /// No description provided for @sectionMessageRows.
  ///
  /// In en, this message translates to:
  /// **'Message rows'**
  String get sectionMessageRows;

  /// No description provided for @colorBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get colorBackground;

  /// No description provided for @colorSurface.
  ///
  /// In en, this message translates to:
  /// **'Surface'**
  String get colorSurface;

  /// No description provided for @colorText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get colorText;

  /// No description provided for @colorSecondary.
  ///
  /// In en, this message translates to:
  /// **'Secondary'**
  String get colorSecondary;

  /// No description provided for @colorAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get colorAccent;

  /// No description provided for @colorSoft.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get colorSoft;

  /// No description provided for @colorSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get colorSuccess;

  /// No description provided for @colorWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get colorWarning;

  /// No description provided for @colorDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger'**
  String get colorDanger;

  /// No description provided for @typeDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get typeDisplay;

  /// No description provided for @typeTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get typeTitle;

  /// No description provided for @typeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get typeSubtitle;

  /// No description provided for @typeBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get typeBody;

  /// No description provided for @typeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get typeSmall;

  /// No description provided for @typeMono.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get typeMono;

  /// No description provided for @actionSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get actionSend;

  /// No description provided for @actionSnooze.
  ///
  /// In en, this message translates to:
  /// **'Snooze'**
  String get actionSnooze;

  /// No description provided for @actionReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get actionReply;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get actionDisabled;

  /// No description provided for @filterUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get filterUnread;

  /// No description provided for @filterAttachments.
  ///
  /// In en, this message translates to:
  /// **'With attachments'**
  String get filterAttachments;

  /// No description provided for @filterPeople.
  ///
  /// In en, this message translates to:
  /// **'People only'**
  String get filterPeople;

  /// Screen reader label for an unread message row
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get messageUnread;

  /// No description provided for @compose.
  ///
  /// In en, this message translates to:
  /// **'Compose'**
  String get compose;

  /// No description provided for @unifiedInbox.
  ///
  /// In en, this message translates to:
  /// **'Unified inbox'**
  String get unifiedInbox;

  /// No description provided for @accounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accounts;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get addAccount;

  /// No description provided for @inbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inbox;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {done} of {total}'**
  String downloading(String done, String total);

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline · retrying'**
  String get offline;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'An account needs its password again'**
  String get signInFailed;

  /// No description provided for @inboxSummary.
  ///
  /// In en, this message translates to:
  /// **'{accounts, plural, =1{1 account} other{{accounts} accounts}} · {unread, plural, =0{all read} other{{unread} unread}}'**
  String inboxSummary(int accounts, int unread);

  /// No description provided for @nothingSelected.
  ///
  /// In en, this message translates to:
  /// **'Pick a message to read it.'**
  String get nothingSelected;

  /// No description provided for @noSubject.
  ///
  /// In en, this message translates to:
  /// **'(no subject)'**
  String get noSubject;

  /// No description provided for @couldNotLoadMessage.
  ///
  /// In en, this message translates to:
  /// **'This message could not be downloaded. Check the connection and try again.'**
  String get couldNotLoadMessage;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @toYouToday.
  ///
  /// In en, this message translates to:
  /// **'to you · today at {time}'**
  String toYouToday(String time);

  /// No description provided for @toYouYesterday.
  ///
  /// In en, this message translates to:
  /// **'to you · yesterday at {time}'**
  String toYouYesterday(String time);

  /// No description provided for @toYouOn.
  ///
  /// In en, this message translates to:
  /// **'to you · {date} at {time}'**
  String toYouOn(String date, String time);

  /// No description provided for @sectionToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get sectionToday;

  /// No description provided for @sectionYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get sectionYesterday;

  /// No description provided for @sectionThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get sectionThisWeek;

  /// No description provided for @sectionThisMonth.
  ///
  /// In en, this message translates to:
  /// **'Earlier this month'**
  String get sectionThisMonth;

  /// No description provided for @sectionOlder.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get sectionOlder;

  /// No description provided for @defaultAccountName.
  ///
  /// In en, this message translates to:
  /// **'Mail'**
  String get defaultAccountName;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailAddress;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @imapServer.
  ///
  /// In en, this message translates to:
  /// **'IMAP server'**
  String get imapServer;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @accountName.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get accountName;

  /// No description provided for @accountColor.
  ///
  /// In en, this message translates to:
  /// **'Account color'**
  String get accountColor;

  /// No description provided for @color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @enterToConnect.
  ///
  /// In en, this message translates to:
  /// **'to connect'**
  String get enterToConnect;

  /// No description provided for @errorWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'The server did not accept this address and password. If your provider uses app passwords, create one and use it here.'**
  String get errorWrongPassword;

  /// No description provided for @errorUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The server could not be reached. Check the server name, the port and your connection.'**
  String get errorUnreachable;

  /// No description provided for @errorInsecure.
  ///
  /// In en, this message translates to:
  /// **'A secure connection to the server could not be made. Check the server name and the security setting.'**
  String get errorInsecure;

  /// No description provided for @errorKeychain.
  ///
  /// In en, this message translates to:
  /// **'The password could not be saved in the system keychain.'**
  String get errorKeychain;

  /// No description provided for @errorOther.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while connecting. Try again.'**
  String get errorOther;

  /// No description provided for @yourAccounts.
  ///
  /// In en, this message translates to:
  /// **'Your accounts'**
  String get yourAccounts;

  /// No description provided for @noAccountsYet.
  ///
  /// In en, this message translates to:
  /// **'Your first account will appear here.'**
  String get noAccountsYet;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @privacyNote.
  ///
  /// In en, this message translates to:
  /// **'Your email stays on this device. We connect straight to your servers, with nobody in between.'**
  String get privacyNote;

  /// No description provided for @newMessage.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get newMessage;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// No description provided for @cc.
  ///
  /// In en, this message translates to:
  /// **'Cc'**
  String get cc;

  /// No description provided for @bcc.
  ///
  /// In en, this message translates to:
  /// **'Bcc'**
  String get bcc;

  /// No description provided for @ccBcc.
  ///
  /// In en, this message translates to:
  /// **'Cc  Bcc'**
  String get ccBcc;

  /// No description provided for @subject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get subject;

  /// No description provided for @messageBody.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageBody;

  /// No description provided for @addRecipient.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addRecipient;

  /// No description provided for @removeRecipient.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String removeRecipient(String name);

  /// No description provided for @undoSendHint.
  ///
  /// In en, this message translates to:
  /// **'You can undo send for {seconds} seconds'**
  String undoSendHint(int seconds);

  /// No description provided for @sendNoRecipients.
  ///
  /// In en, this message translates to:
  /// **'Add at least one recipient.'**
  String get sendNoRecipients;

  /// No description provided for @sendBadAddress.
  ///
  /// In en, this message translates to:
  /// **'“{address}” is not an email address.'**
  String sendBadAddress(String address);

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sending;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @draftDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Draft discarded'**
  String get draftDiscarded;

  /// No description provided for @sendErrorPassword.
  ///
  /// In en, this message translates to:
  /// **'The outgoing server didn\'t accept the password. Your message is still here.'**
  String get sendErrorPassword;

  /// No description provided for @sendErrorUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the outgoing server. Your message is still here.'**
  String get sendErrorUnreachable;

  /// No description provided for @sendErrorRejected.
  ///
  /// In en, this message translates to:
  /// **'The outgoing server refused the message. Your message is still here.'**
  String get sendErrorRejected;

  /// No description provided for @sendErrorOther.
  ///
  /// In en, this message translates to:
  /// **'The message couldn\'t be sent. Your message is still here.'**
  String get sendErrorOther;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'{step} of {total}'**
  String stepOf(int step, int total);

  /// No description provided for @whatsYourEmail.
  ///
  /// In en, this message translates to:
  /// **'What’s your email?'**
  String get whatsYourEmail;

  /// No description provided for @findSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'We’ll find the server settings for you.'**
  String get findSettingsHint;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @lookingUp.
  ///
  /// In en, this message translates to:
  /// **'Looking…'**
  String get lookingUp;

  /// No description provided for @setUpManually.
  ///
  /// In en, this message translates to:
  /// **'Set up manually'**
  String get setUpManually;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @weFoundSettings.
  ///
  /// In en, this message translates to:
  /// **'We found your settings'**
  String get weFoundSettings;

  /// No description provided for @incoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get incoming;

  /// No description provided for @outgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get outgoing;

  /// No description provided for @incomingAndOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Incoming and outgoing'**
  String get incomingAndOutgoing;

  /// No description provided for @guessedSettings.
  ///
  /// In en, this message translates to:
  /// **'These are the usual settings for your domain. If connecting fails, check them.'**
  String get guessedSettings;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @yourNameHint.
  ///
  /// In en, this message translates to:
  /// **'Shown to the people you write to. Optional.'**
  String get yourNameHint;

  /// No description provided for @settingsNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t find the settings for this address. Your provider’s help pages list them.'**
  String get settingsNotFound;

  /// No description provided for @smtpServer.
  ///
  /// In en, this message translates to:
  /// **'SMTP server'**
  String get smtpServer;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @usedForBoth.
  ///
  /// In en, this message translates to:
  /// **'Used for both incoming and outgoing mail.'**
  String get usedForBoth;

  /// No description provided for @verifyAndConnect.
  ///
  /// In en, this message translates to:
  /// **'Verify and connect'**
  String get verifyAndConnect;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// No description provided for @movedToTrash.
  ///
  /// In en, this message translates to:
  /// **'Moved to Trash'**
  String get movedToTrash;

  /// No description provided for @actionFailed.
  ///
  /// In en, this message translates to:
  /// **'The message couldn’t be moved. It’s back in the inbox.'**
  String get actionFailed;

  /// No description provided for @replyTitle.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get replyTitle;

  /// No description provided for @quoteHeader.
  ///
  /// In en, this message translates to:
  /// **'On {date}, {name} wrote:'**
  String quoteHeader(String date, String name);

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get search;

  /// No description provided for @searchAllAccounts.
  ///
  /// In en, this message translates to:
  /// **'Search all accounts'**
  String get searchAllAccounts;

  /// No description provided for @searchResults.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No results} =1{1 result} other{{count} results}}'**
  String searchResults(int count);

  /// No description provided for @searchFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get searchFilters;

  /// No description provided for @filterLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get filterLastMonth;

  /// No description provided for @filterAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get filterAccount;

  /// No description provided for @searchOperators.
  ///
  /// In en, this message translates to:
  /// **'Operators'**
  String get searchOperators;

  /// No description provided for @operatorNameHint.
  ///
  /// In en, this message translates to:
  /// **'name'**
  String get operatorNameHint;

  /// No description provided for @operatorDateHint.
  ///
  /// In en, this message translates to:
  /// **'date'**
  String get operatorDateHint;

  /// No description provided for @searchPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get searchPeople;

  /// No description provided for @searchEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get searchEmail;

  /// No description provided for @personEmails.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 email} other{{count} emails}}'**
  String personEmails(int count);

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get searchNoResults;

  /// No description provided for @searchNoResultsHint.
  ///
  /// In en, this message translates to:
  /// **'Try fewer words or another spelling.'**
  String get searchNoResultsHint;

  /// No description provided for @searchNoResultsFilters.
  ///
  /// In en, this message translates to:
  /// **'No results with these filters'**
  String get searchNoResultsFilters;

  /// No description provided for @searchNoResultsFiltersHint.
  ///
  /// In en, this message translates to:
  /// **'Remove a filter or operator to widen the search.'**
  String get searchNoResultsFiltersHint;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @searchEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Search every account by word, sender or date, even offline.'**
  String get searchEmptyHint;

  /// No description provided for @searchMatches.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 match} other{{count} matches}}'**
  String searchMatches(int count);

  /// No description provided for @openConversation.
  ///
  /// In en, this message translates to:
  /// **'Open conversation'**
  String get openConversation;

  /// No description provided for @noMessageToShow.
  ///
  /// In en, this message translates to:
  /// **'No message to show'**
  String get noMessageToShow;

  /// No description provided for @searchStats.
  ///
  /// In en, this message translates to:
  /// **'Searched {accounts, plural, =1{1 account} other{{accounts} accounts}} · {emails} emails · {seconds} s · local index, works offline'**
  String searchStats(int accounts, String emails, String seconds);

  /// No description provided for @keyMove.
  ///
  /// In en, this message translates to:
  /// **'move'**
  String get keyMove;

  /// No description provided for @keyOpen.
  ///
  /// In en, this message translates to:
  /// **'open'**
  String get keyOpen;

  /// No description provided for @privacyImagesBlocked.
  ///
  /// In en, this message translates to:
  /// **'Images blocked'**
  String get privacyImagesBlocked;

  /// No description provided for @privacyImagesBlockedStopped.
  ///
  /// In en, this message translates to:
  /// **'Images blocked · {count, plural, =1{1 tracker stopped} other{{count} trackers stopped}}'**
  String privacyImagesBlockedStopped(int count);

  /// No description provided for @privacyLoadingImages.
  ///
  /// In en, this message translates to:
  /// **'Loading images…'**
  String get privacyLoadingImages;

  /// No description provided for @privacyImagesLoaded.
  ///
  /// In en, this message translates to:
  /// **'Images loaded'**
  String get privacyImagesLoaded;

  /// No description provided for @privacyImagesLoadedStopped.
  ///
  /// In en, this message translates to:
  /// **'Images loaded · trackers still stopped'**
  String get privacyImagesLoadedStopped;

  /// No description provided for @privacyTrackersStopped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tracker stopped} other{{count} trackers stopped}}'**
  String privacyTrackersStopped(int count);

  /// No description provided for @privacyLinksCleaned.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 link cleaned} other{{count} links cleaned}}'**
  String privacyLinksCleaned(int count);

  /// No description provided for @privacySheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy for this message'**
  String get privacySheetTitle;

  /// No description provided for @privacySheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The sender can’t tell if or when you opened it.'**
  String get privacySheetSubtitle;

  /// No description provided for @trackerPixel.
  ///
  /// In en, this message translates to:
  /// **'Open pixel'**
  String get trackerPixel;

  /// No description provided for @trackerFont.
  ///
  /// In en, this message translates to:
  /// **'Remote font'**
  String get trackerFont;

  /// No description provided for @trackerStyle.
  ///
  /// In en, this message translates to:
  /// **'Remote style'**
  String get trackerStyle;

  /// No description provided for @trackerLinks.
  ///
  /// In en, this message translates to:
  /// **'Tracked links'**
  String get trackerLinks;

  /// No description provided for @trackerStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get trackerStopped;

  /// No description provided for @loadImagesOnce.
  ///
  /// In en, this message translates to:
  /// **'Load images once'**
  String get loadImagesOnce;

  /// No description provided for @imagesAlreadyLoaded.
  ///
  /// In en, this message translates to:
  /// **'Images already loaded'**
  String get imagesAlreadyLoaded;

  /// No description provided for @trustSender.
  ///
  /// In en, this message translates to:
  /// **'Always trust {name}'**
  String trustSender(String name);

  /// No description provided for @senderTrusted.
  ///
  /// In en, this message translates to:
  /// **'{name} is trusted'**
  String senderTrusted(String name);

  /// No description provided for @alwaysBlockImages.
  ///
  /// In en, this message translates to:
  /// **'Always block remote images'**
  String get alwaysBlockImages;

  /// No description provided for @alwaysBlockImagesHint.
  ///
  /// In en, this message translates to:
  /// **'Applies to all untrusted senders'**
  String get alwaysBlockImagesHint;

  /// No description provided for @imageNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Image not loaded'**
  String get imageNotLoaded;

  /// No description provided for @suspiciousLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Check this link'**
  String get suspiciousLinkTitle;

  /// No description provided for @suspiciousLinkBody.
  ///
  /// In en, this message translates to:
  /// **'The text shows {shown}, but the link goes to {real}.'**
  String suspiciousLinkBody(String shown, String real);

  /// No description provided for @openAnyway.
  ///
  /// In en, this message translates to:
  /// **'Open anyway'**
  String get openAnyway;

  /// No description provided for @dontOpen.
  ///
  /// In en, this message translates to:
  /// **'Don’t open'**
  String get dontOpen;

  /// No description provided for @riskProgram.
  ///
  /// In en, this message translates to:
  /// **'A program that can run'**
  String get riskProgram;

  /// No description provided for @riskDisguised.
  ///
  /// In en, this message translates to:
  /// **'A program, named like a {kind}'**
  String riskDisguised(String kind);

  /// No description provided for @riskMacros.
  ///
  /// In en, this message translates to:
  /// **'Has macros that can run'**
  String get riskMacros;

  /// No description provided for @riskLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked with a password'**
  String get riskLocked;

  /// No description provided for @riskOpenProgram.
  ///
  /// In en, this message translates to:
  /// **'Open this program?'**
  String get riskOpenProgram;

  /// No description provided for @riskOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open this file?'**
  String get riskOpenFile;

  /// No description provided for @riskOpenArchive.
  ///
  /// In en, this message translates to:
  /// **'Open this archive?'**
  String get riskOpenArchive;

  /// No description provided for @riskBodyProgram.
  ///
  /// In en, this message translates to:
  /// **'{name} is a program. Programs from email can take over your device. Open it only if you were expecting it.'**
  String riskBodyProgram(String name);

  /// No description provided for @riskBodyDisguised.
  ///
  /// In en, this message translates to:
  /// **'{name} looks like a {kind}, but it is a program. Programs from email can take over your device. Open it only if you were expecting it.'**
  String riskBodyDisguised(String name, String kind);

  /// No description provided for @riskBodyMacros.
  ///
  /// In en, this message translates to:
  /// **'{name} has macros, which can run when it opens. Open it only if you were expecting it.'**
  String riskBodyMacros(String name);

  /// No description provided for @riskBodyLocked.
  ///
  /// In en, this message translates to:
  /// **'{name} is locked with a password, so nothing can look inside it. Open it only if you were expecting it.'**
  String riskBodyLocked(String name);

  /// No description provided for @riskFileFrom.
  ///
  /// In en, this message translates to:
  /// **'{name} · {size} · from {email}'**
  String riskFileFrom(String name, String size, String email);

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @backToMail.
  ///
  /// In en, this message translates to:
  /// **'Back to mail'**
  String get backToMail;

  /// No description provided for @settingsAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get settingsAccountsTitle;

  /// No description provided for @settingsAccountsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One IMAP mailbox.} other{{count} IMAP mailboxes, one Inbox.}} Color shows where each email comes from.'**
  String settingsAccountsSubtitle(int count);

  /// No description provided for @accountKindImap.
  ///
  /// In en, this message translates to:
  /// **'{email} · IMAP'**
  String accountKindImap(String email);

  /// No description provided for @addAccountShort.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get addAccountShort;

  /// No description provided for @addAccountNote.
  ///
  /// In en, this message translates to:
  /// **'IMAP and SMTP. Gmail, iCloud and Fastmail set themselves up.'**
  String get addAccountNote;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & security'**
  String get privacyTitle;

  /// No description provided for @privacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Everything happens on this device. No data leaves your mailbox.'**
  String get privacySubtitle;

  /// No description provided for @blockImagesSetting.
  ///
  /// In en, this message translates to:
  /// **'Block remote images'**
  String get blockImagesSetting;

  /// No description provided for @blockImagesSettingHint.
  ///
  /// In en, this message translates to:
  /// **'Images load only when you ask.'**
  String get blockImagesSettingHint;

  /// No description provided for @stopPixelsSetting.
  ///
  /// In en, this message translates to:
  /// **'Stop tracking pixels'**
  String get stopPixelsSetting;

  /// No description provided for @stopPixelsSettingHint.
  ///
  /// In en, this message translates to:
  /// **'Senders can’t tell if or when you open a message.'**
  String get stopPixelsSettingHint;

  /// No description provided for @cleanLinksSetting.
  ///
  /// In en, this message translates to:
  /// **'Clean links'**
  String get cleanLinksSetting;

  /// No description provided for @cleanLinksSettingHint.
  ///
  /// In en, this message translates to:
  /// **'Strips utm and tracking parameters before opening.'**
  String get cleanLinksSettingHint;

  /// No description provided for @warnLinksSetting.
  ///
  /// In en, this message translates to:
  /// **'Warn about suspicious links'**
  String get warnLinksSetting;

  /// No description provided for @warnLinksSettingHint.
  ///
  /// In en, this message translates to:
  /// **'Asks before opening a link that shows one address and goes to another.'**
  String get warnLinksSettingHint;

  /// No description provided for @last30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get last30Days;

  /// No description provided for @trackersStoppedLabel.
  ///
  /// In en, this message translates to:
  /// **'trackers stopped'**
  String get trackersStoppedLabel;

  /// No description provided for @linksCleanedLabel.
  ///
  /// In en, this message translates to:
  /// **'links cleaned'**
  String get linksCleanedLabel;

  /// No description provided for @privacyStatsDetail.
  ///
  /// In en, this message translates to:
  /// **'Open pixels {pixels} · remote fonts and styles {styles} · {suspicious, plural, =1{1 suspicious link flagged} other{{suspicious} suspicious links flagged}}'**
  String privacyStatsDetail(String pixels, String styles, int suspicious);

  /// No description provided for @trustedSenders.
  ///
  /// In en, this message translates to:
  /// **'Trusted senders'**
  String get trustedSenders;

  /// No description provided for @trustedSendersHint.
  ///
  /// In en, this message translates to:
  /// **'images always load'**
  String get trustedSendersHint;

  /// No description provided for @trustedSince.
  ///
  /// In en, this message translates to:
  /// **'{email} · since {date}'**
  String trustedSince(String email, String date);

  /// No description provided for @removeTrusted.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeTrusted;

  /// No description provided for @noTrustedSenders.
  ///
  /// In en, this message translates to:
  /// **'No trusted senders. Images stay blocked for everyone.'**
  String get noTrustedSenders;

  /// No description provided for @appVersionLine.
  ///
  /// In en, this message translates to:
  /// **'Piuma Mail {version} · GPL-3.0'**
  String appVersionLine(String version);

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get attachFile;

  /// No description provided for @removeAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String removeAttachment(String name);

  /// No description provided for @attachmentLabel.
  ///
  /// In en, this message translates to:
  /// **'{name}, {size}'**
  String attachmentLabel(String name, String size);

  /// No description provided for @attachmentSaved.
  ///
  /// In en, this message translates to:
  /// **'{name} saved in Downloads'**
  String attachmentSaved(String name);

  /// No description provided for @attachmentNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t download {name}. Check the connection and try again.'**
  String attachmentNotSaved(String name);

  /// No description provided for @filesTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Attachments can be up to {max} in all. Remove some and try again.'**
  String filesTooLarge(String max);

  /// No description provided for @fileNotRead.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t read {name}.'**
  String fileNotRead(String name);

  /// No description provided for @folderSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get folderSent;

  /// No description provided for @folderArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get folderArchive;

  /// No description provided for @folderSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One account} other{{count} accounts}}'**
  String folderSummary(int count);

  /// No description provided for @toPeopleToday.
  ///
  /// In en, this message translates to:
  /// **'to {people} · today at {time}'**
  String toPeopleToday(String people, String time);

  /// No description provided for @toPeopleYesterday.
  ///
  /// In en, this message translates to:
  /// **'to {people} · yesterday at {time}'**
  String toPeopleYesterday(String people, String time);

  /// No description provided for @toPeopleOn.
  ///
  /// In en, this message translates to:
  /// **'to {people} · {date} at {time}'**
  String toPeopleOn(String people, String date, String time);

  /// No description provided for @emptyFolder.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get emptyFolder;

  /// No description provided for @threadMessages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message} other{{count} messages}}'**
  String threadMessages(int count);

  /// No description provided for @conversationSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} messages · {people}'**
  String conversationSummary(int count, String people);

  /// No description provided for @readMessages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 read message} other{{count} read messages}}'**
  String readMessages(int count);

  /// No description provided for @newMessages.
  ///
  /// In en, this message translates to:
  /// **'{count} new'**
  String newMessages(int count);

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get you;

  /// No description provided for @quotedTextHidden.
  ///
  /// In en, this message translates to:
  /// **'··· quoted text hidden'**
  String get quotedTextHidden;

  /// No description provided for @showQuotedText.
  ///
  /// In en, this message translates to:
  /// **'Show quoted text'**
  String get showQuotedText;

  /// No description provided for @youName.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get youName;

  /// No description provided for @yesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday {time}'**
  String yesterdayAt(String time);

  /// No description provided for @pickMessage.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get pickMessage;

  /// No description provided for @unpickMessage.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get unpickMessage;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @pickedOf.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} selected'**
  String pickedOf(int count, int total);

  /// No description provided for @deselect.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get deselect;

  /// No description provided for @conversationsPicked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{conversation selected} other{conversations selected}}'**
  String conversationsPicked(int count);

  /// No description provided for @pickedFromOne.
  ///
  /// In en, this message translates to:
  /// **'from {name}'**
  String pickedFromOne(String name);

  /// No description provided for @pickedFromList.
  ///
  /// In en, this message translates to:
  /// **'from {names} and {last}'**
  String pickedFromList(String names, String last);

  /// No description provided for @pickedFromMore.
  ///
  /// In en, this message translates to:
  /// **'from {names} and {count} more'**
  String pickedFromMore(String names, int count);

  /// No description provided for @andMore.
  ///
  /// In en, this message translates to:
  /// **'{name} and {count} more'**
  String andMore(String name, int count);

  /// No description provided for @markRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markRead;

  /// No description provided for @markUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread'**
  String get markUnread;

  /// No description provided for @hintArchive.
  ///
  /// In en, this message translates to:
  /// **'archive'**
  String get hintArchive;

  /// No description provided for @hintUnread.
  ///
  /// In en, this message translates to:
  /// **'unread'**
  String get hintUnread;

  /// No description provided for @hintDeselect.
  ///
  /// In en, this message translates to:
  /// **'deselect'**
  String get hintDeselect;

  /// No description provided for @archivedMany.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Archived} other{{count} conversations archived}}'**
  String archivedMany(int count);

  /// No description provided for @trashedMany.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Moved to Trash} other{{count} conversations moved to Trash}}'**
  String trashedMany(int count);

  /// No description provided for @seenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach the server. Read and unread are back as they were.'**
  String get seenFailed;

  /// No description provided for @signaturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Signatures'**
  String get signaturesTitle;

  /// No description provided for @newSignature.
  ///
  /// In en, this message translates to:
  /// **'New signature'**
  String get newSignature;

  /// No description provided for @newSignatureLabel.
  ///
  /// In en, this message translates to:
  /// **'New signature'**
  String get newSignatureLabel;

  /// No description provided for @noSignatures.
  ///
  /// In en, this message translates to:
  /// **'No signatures yet. Make one with New signature.'**
  String get noSignatures;

  /// No description provided for @signatureTemplate.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get signatureTemplate;

  /// No description provided for @signatureLogo.
  ///
  /// In en, this message translates to:
  /// **'Logo'**
  String get signatureLogo;

  /// No description provided for @signatureLabelField.
  ///
  /// In en, this message translates to:
  /// **'Signature name'**
  String get signatureLabelField;

  /// No description provided for @signatureAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get signatureAccount;

  /// No description provided for @signatureName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get signatureName;

  /// No description provided for @signatureRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get signatureRole;

  /// No description provided for @signatureCompany.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get signatureCompany;

  /// No description provided for @signaturePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get signaturePhone;

  /// No description provided for @signatureWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get signatureWebsite;

  /// No description provided for @signatureAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get signatureAccent;

  /// No description provided for @accentBlue.
  ///
  /// In en, this message translates to:
  /// **'Accent blue'**
  String get accentBlue;

  /// No description provided for @accentBlack.
  ///
  /// In en, this message translates to:
  /// **'Accent black'**
  String get accentBlack;

  /// No description provided for @accentTerracotta.
  ///
  /// In en, this message translates to:
  /// **'Accent terracotta'**
  String get accentTerracotta;

  /// No description provided for @signatureWhen.
  ///
  /// In en, this message translates to:
  /// **'When to use it'**
  String get signatureWhen;

  /// No description provided for @signatureForNew.
  ///
  /// In en, this message translates to:
  /// **'New emails from {email}'**
  String signatureForNew(String email);

  /// No description provided for @signatureForReplies.
  ///
  /// In en, this message translates to:
  /// **'Replies and forwards'**
  String get signatureForReplies;

  /// No description provided for @signatureNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get signatureNone;

  /// No description provided for @deleteSignature.
  ///
  /// In en, this message translates to:
  /// **'Delete signature'**
  String get deleteSignature;

  /// No description provided for @signatureDeleteHint.
  ///
  /// In en, this message translates to:
  /// **'Emails already sent keep it.'**
  String get signatureDeleteHint;

  /// No description provided for @signaturePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get signaturePreview;

  /// No description provided for @previewLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get previewLight;

  /// No description provided for @previewDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get previewDark;

  /// No description provided for @previewText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get previewText;

  /// No description provided for @signatureSampleText.
  ///
  /// In en, this message translates to:
  /// **'Hi Luca,\nthe final files are attached. Let me know if you need anything else.\n\nTalk soon,'**
  String get signatureSampleText;

  /// No description provided for @signatureNote.
  ///
  /// In en, this message translates to:
  /// **'No images: the signature arrives clean even where images are blocked, and the plain-text version is created for you.'**
  String get signatureNote;

  /// No description provided for @signatureNoteLogo.
  ///
  /// In en, this message translates to:
  /// **'The logo travels inside the email (max 40 KB) with alt text, so it never asks to “load images” and tracks no one. The plain-text version is created for you.'**
  String get signatureNoteLogo;

  /// No description provided for @signatureUseAll.
  ///
  /// In en, this message translates to:
  /// **'all'**
  String get signatureUseAll;

  /// No description provided for @signatureUseNew.
  ///
  /// In en, this message translates to:
  /// **'new emails'**
  String get signatureUseNew;

  /// No description provided for @signatureUseReplies.
  ///
  /// In en, this message translates to:
  /// **'replies and forwards'**
  String get signatureUseReplies;

  /// No description provided for @signatureUseNone.
  ///
  /// In en, this message translates to:
  /// **'not in use'**
  String get signatureUseNone;

  /// No description provided for @templateMinimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get templateMinimal;

  /// No description provided for @templateClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get templateClassic;

  /// No description provided for @templateMonogram.
  ///
  /// In en, this message translates to:
  /// **'Monogram'**
  String get templateMonogram;

  /// No description provided for @templateLogo.
  ///
  /// In en, this message translates to:
  /// **'With logo'**
  String get templateLogo;

  /// No description provided for @noLogo.
  ///
  /// In en, this message translates to:
  /// **'NO LOGO'**
  String get noLogo;

  /// No description provided for @logoHint.
  ///
  /// In en, this message translates to:
  /// **'PNG or JPEG, shrunk to 40 KB automatically'**
  String get logoHint;

  /// No description provided for @removeLogo.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLogo;

  /// No description provided for @uploadLogo.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get uploadLogo;

  /// No description provided for @logoTooBig.
  ///
  /// In en, this message translates to:
  /// **'This logo stays over 40 KB even when shrunk. Try a simpler one.'**
  String get logoTooBig;

  /// No description provided for @logoNotImage.
  ///
  /// In en, this message translates to:
  /// **'Pick a PNG or JPEG image.'**
  String get logoNotImage;

  /// No description provided for @signatureChip.
  ///
  /// In en, this message translates to:
  /// **'Signature · {label}'**
  String signatureChip(String label);

  /// No description provided for @noSignature.
  ///
  /// In en, this message translates to:
  /// **'No signature'**
  String get noSignature;

  /// No description provided for @manageSignatures.
  ///
  /// In en, this message translates to:
  /// **'Manage signatures…'**
  String get manageSignatures;

  /// No description provided for @signatureUsedNew.
  ///
  /// In en, this message translates to:
  /// **'New emails'**
  String get signatureUsedNew;

  /// No description provided for @signatureUsedReplies.
  ///
  /// In en, this message translates to:
  /// **'Replies'**
  String get signatureUsedReplies;

  /// No description provided for @composeSignatureNote.
  ///
  /// In en, this message translates to:
  /// **'The signature follows the From account: its signature for new emails, its short one for replies and forwards.'**
  String get composeSignatureNote;

  /// No description provided for @noticeOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get noticeOpen;

  /// No description provided for @noticeChannel.
  ///
  /// In en, this message translates to:
  /// **'New mail'**
  String get noticeChannel;

  /// No description provided for @noticeTitleMany.
  ///
  /// In en, this message translates to:
  /// **'{sender} · {count, plural, =1{1 email} other{{count} emails}}'**
  String noticeTitleMany(String sender, int count);

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsLead.
  ///
  /// In en, this message translates to:
  /// **'Few, and only when they matter.'**
  String get notificationsLead;

  /// No description provided for @notifyAbout.
  ///
  /// In en, this message translates to:
  /// **'Notify me about'**
  String get notifyAbout;

  /// No description provided for @notifyPeople.
  ///
  /// In en, this message translates to:
  /// **'People only'**
  String get notifyPeople;

  /// No description provided for @notifyPeopleHint.
  ///
  /// In en, this message translates to:
  /// **'Email written by people. No newsletters, receipts or automated messages.'**
  String get notifyPeopleHint;

  /// No description provided for @notifyRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get notifyRecommended;

  /// No description provided for @notifyAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get notifyAll;

  /// No description provided for @notifyAllHint.
  ///
  /// In en, this message translates to:
  /// **'Every new email that lands in the Inbox.'**
  String get notifyAllHint;

  /// No description provided for @notifyOff.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get notifyOff;

  /// No description provided for @notifyOffHint.
  ///
  /// In en, this message translates to:
  /// **'Check whenever you like. No badges, no sounds.'**
  String get notifyOffHint;

  /// No description provided for @quietHours.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours'**
  String get quietHours;

  /// No description provided for @quietTitle.
  ///
  /// In en, this message translates to:
  /// **'Every night'**
  String get quietTitle;

  /// No description provided for @quietHint.
  ///
  /// In en, this message translates to:
  /// **'Email still arrives, quietly.'**
  String get quietHint;

  /// No description provided for @quietFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get quietFrom;

  /// No description provided for @quietTo.
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get quietTo;

  /// No description provided for @quietFromLabel.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours start at {time}'**
  String quietFromLabel(String time);

  /// No description provided for @quietToLabel.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours end at {time}'**
  String quietToLabel(String time);

  /// No description provided for @phoneSearch.
  ///
  /// In en, this message translates to:
  /// **'Search {count, plural, =1{1 account} other{{count} accounts}}'**
  String phoneSearch(int count);

  /// No description provided for @phoneAccountsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get phoneAccountsAll;

  /// No description provided for @phoneAccountsLabel.
  ///
  /// In en, this message translates to:
  /// **'Showing all {count, plural, =1{1 account} other{{count} accounts}}'**
  String phoneAccountsLabel(int count);

  /// No description provided for @composeMessage.
  ///
  /// In en, this message translates to:
  /// **'Compose a message'**
  String get composeMessage;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// No description provided for @quickReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Reply to {name}…'**
  String quickReplyHint(String name);

  /// No description provided for @sendReply.
  ///
  /// In en, this message translates to:
  /// **'Send reply'**
  String get sendReply;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @pickAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get pickAll;

  /// No description provided for @pickNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pickNone;

  /// No description provided for @pickRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get pickRead;

  /// No description provided for @pickUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get pickUnread;

  /// No description provided for @phoneSelectedWord.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{selected}}'**
  String phoneSelectedWord(int count);

  /// No description provided for @phoneOfTotal.
  ///
  /// In en, this message translates to:
  /// **'of {total}'**
  String phoneOfTotal(int total);

  /// No description provided for @phoneSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} selected'**
  String phoneSelected(int count, int total);

  /// No description provided for @phoneSelectActions.
  ///
  /// In en, this message translates to:
  /// **'Actions on selected'**
  String get phoneSelectActions;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// Settings: heading over Writing, Reading, Organizing and Calendars
  ///
  /// In en, this message translates to:
  /// **'Mail'**
  String get settingsMail;

  /// Settings: heading over Appearance, Notifications, Privacy and Devices & sync
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsApp;

  /// Settings › Writing: signatures and templates
  ///
  /// In en, this message translates to:
  /// **'Writing'**
  String get writingTitle;

  /// Settings › Reading: density, preview lines, on-device helpers
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get readingTitle;

  /// No description provided for @readingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How the list looks, and what helps you read.'**
  String get readingSubtitle;

  /// Settings › Organizing: zone switches, rules, folders and labels
  ///
  /// In en, this message translates to:
  /// **'Organizing'**
  String get organizingTitle;

  /// No description provided for @organizingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Zones, rules, folders and labels.'**
  String get organizingSubtitle;

  /// No description provided for @signaturesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 signature} other{{count} signatures}}'**
  String signaturesCount(int count);

  /// No description provided for @openSourceLine.
  ///
  /// In en, this message translates to:
  /// **'Open source · GPL-3.0'**
  String get openSourceLine;

  /// No description provided for @motto.
  ///
  /// In en, this message translates to:
  /// **'Mail, made light.'**
  String get motto;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Piuma Mail'**
  String get appName;

  /// No description provided for @phoneAccountsMenu.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 account} other{{count} accounts}}, accounts and Settings'**
  String phoneAccountsMenu(int count);

  /// No description provided for @allAccounts.
  ///
  /// In en, this message translates to:
  /// **'All accounts'**
  String get allAccounts;

  /// No description provided for @allAccountsDetail.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 inbox} other{{count} inboxes together}}'**
  String allAccountsDetail(int count);

  /// No description provided for @phoneAccountMenu.
  ///
  /// In en, this message translates to:
  /// **'{name} only, accounts and Settings'**
  String phoneAccountMenu(String name);

  /// No description provided for @accountOnly.
  ///
  /// In en, this message translates to:
  /// **'{name} only'**
  String accountOnly(String name);

  /// No description provided for @showAllAccounts.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAllAccounts;

  /// No description provided for @phoneFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get phoneFolders;

  /// No description provided for @phoneSearchOne.
  ///
  /// In en, this message translates to:
  /// **'Search {name}'**
  String phoneSearchOne(String name);

  /// No description provided for @welcomeLead.
  ///
  /// In en, this message translates to:
  /// **'Connect your IMAP accounts and read everything in one inbox, without the noise.'**
  String get welcomeLead;

  /// No description provided for @staysOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Your email stays on your device'**
  String get staysOnDevice;

  /// No description provided for @editServers.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editServers;

  /// No description provided for @serverHost.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get serverHost;

  /// No description provided for @offlineTitle.
  ///
  /// In en, this message translates to:
  /// **'You’re offline'**
  String get offlineTitle;

  /// No description provided for @offlineDetail.
  ///
  /// In en, this message translates to:
  /// **'outgoing email sends once you’re back online'**
  String get offlineDetail;

  /// No description provided for @downloadingAccount.
  ///
  /// In en, this message translates to:
  /// **'Downloading {name}'**
  String downloadingAccount(String name);

  /// No description provided for @downloadingCount.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String downloadingCount(String done, String total);

  /// No description provided for @accountCantConnect.
  ///
  /// In en, this message translates to:
  /// **'The {name} account can’t connect'**
  String accountCantConnect(String name);

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Did the password change? Email for {email} has stopped arriving.'**
  String passwordChanged(String email);

  /// No description provided for @signInAgain.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get signInAgain;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @signInTo.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {name}'**
  String signInTo(String name);

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @allCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'All caught up'**
  String get allCaughtUp;

  /// No description provided for @allCaughtUpDetail.
  ///
  /// In en, this message translates to:
  /// **'Nobody is waiting on you. The rest of the day is yours.'**
  String get allCaughtUpDetail;

  /// No description provided for @countOf.
  ///
  /// In en, this message translates to:
  /// **'of'**
  String get countOf;

  /// No description provided for @draftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved'**
  String get draftSaved;

  /// No description provided for @draftNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Not saved'**
  String get draftNotSaved;

  /// No description provided for @draftNotSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Draft not saved'**
  String get draftNotSavedToast;

  /// No description provided for @reopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get reopen;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @noRecipients.
  ///
  /// In en, this message translates to:
  /// **'No recipients'**
  String get noRecipients;

  /// No description provided for @folderDrafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get folderDrafts;

  /// No description provided for @accountFolders.
  ///
  /// In en, this message translates to:
  /// **'{name} folders'**
  String accountFolders(String name);

  /// No description provided for @moveShort.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveShort;

  /// No description provided for @moveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to…'**
  String get moveTo;

  /// No description provided for @moveToIn.
  ///
  /// In en, this message translates to:
  /// **'Move to folder in {name}'**
  String moveToIn(String name);

  /// No description provided for @noFoldersMatch.
  ///
  /// In en, this message translates to:
  /// **'No folder by that name'**
  String get noFoldersMatch;

  /// No description provided for @noOtherFolders.
  ///
  /// In en, this message translates to:
  /// **'{name} has no other folders yet'**
  String noOtherFolders(String name);

  /// No description provided for @movedMany.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Moved to {folder}} other{{count} conversations moved to {folder}}}'**
  String movedMany(int count, String folder);

  /// No description provided for @outboxHeader.
  ///
  /// In en, this message translates to:
  /// **'Outbox · {count}'**
  String outboxHeader(int count);

  /// No description provided for @outboxTo.
  ///
  /// In en, this message translates to:
  /// **'To {names}'**
  String outboxTo(String names);

  /// No description provided for @outboxWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get outboxWaiting;

  /// No description provided for @outboxNotSent.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get outboxNotSent;

  /// No description provided for @outboxRefused.
  ///
  /// In en, this message translates to:
  /// **'The server refused it: {reason}'**
  String outboxRefused(String reason);

  /// No description provided for @inOutbox.
  ///
  /// In en, this message translates to:
  /// **'In the Outbox · it goes once you’re back online'**
  String get inOutbox;

  /// No description provided for @editAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editAction;

  /// No description provided for @backgroundTitle.
  ///
  /// In en, this message translates to:
  /// **'New mail as it arrives'**
  String get backgroundTitle;

  /// No description provided for @backgroundBody.
  ///
  /// In en, this message translates to:
  /// **'Piuma stays connected to your accounts, with no server in between. Android will ask two things: to show notifications, and to let Piuma run in the background.'**
  String get backgroundBody;

  /// No description provided for @newMailHeading.
  ///
  /// In en, this message translates to:
  /// **'New mail'**
  String get newMailHeading;

  /// No description provided for @deliveryInstant.
  ///
  /// In en, this message translates to:
  /// **'As it arrives'**
  String get deliveryInstant;

  /// No description provided for @deliveryInstantHint.
  ///
  /// In en, this message translates to:
  /// **'Keeps a silent notice in the shade'**
  String get deliveryInstantHint;

  /// No description provided for @deliveryPeriodic.
  ///
  /// In en, this message translates to:
  /// **'Every 15 minutes'**
  String get deliveryPeriodic;

  /// No description provided for @deliveryPeriodicHint.
  ///
  /// In en, this message translates to:
  /// **'No notice; Android may wait longer'**
  String get deliveryPeriodicHint;

  /// No description provided for @folderNewsletters.
  ///
  /// In en, this message translates to:
  /// **'Newsletters'**
  String get folderNewsletters;

  /// No description provided for @newslettersTileLabel.
  ///
  /// In en, this message translates to:
  /// **'Newsletters, {count} unread'**
  String newslettersTileLabel(int count);

  /// No description provided for @newsletterRowMeta.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min · {when}'**
  String newsletterRowMeta(int minutes, String when);

  /// No description provided for @newsletterReadTime.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min read · arrived at {time}'**
  String newsletterReadTime(int minutes, String time);

  /// No description provided for @newsletterArrived.
  ///
  /// In en, this message translates to:
  /// **'Arrived at {time}'**
  String newsletterArrived(String time);

  /// No description provided for @newsletterArrivedOn.
  ///
  /// In en, this message translates to:
  /// **'Arrived on {date}'**
  String newsletterArrivedOn(String date);

  /// No description provided for @newsletterReadTimeOn.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min read · arrived on {date}'**
  String newsletterReadTimeOn(int minutes, String date);

  /// No description provided for @dayToday.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get dayToday;

  /// No description provided for @dayYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get dayYesterday;

  /// No description provided for @readLater.
  ///
  /// In en, this message translates to:
  /// **'Read later'**
  String get readLater;

  /// No description provided for @readLaterDone.
  ///
  /// In en, this message translates to:
  /// **'Kept as unread'**
  String get readLaterDone;

  /// No description provided for @unsubscribe.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe'**
  String get unsubscribe;

  /// No description provided for @unsubscribeTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe from {sender}?'**
  String unsubscribeTitle(String sender);

  /// No description provided for @unsubscribeOneClick.
  ///
  /// In en, this message translates to:
  /// **'{sender} gets one request to stop. Nothing opens, and what already came stays here.'**
  String unsubscribeOneClick(String sender);

  /// No description provided for @unsubscribeMail.
  ///
  /// In en, this message translates to:
  /// **'A message goes from your account to {address} to ask. What already came stays here.'**
  String unsubscribeMail(String address);

  /// No description provided for @unsubscribePage.
  ///
  /// In en, this message translates to:
  /// **'Their unsubscribe page opens in the browser.'**
  String get unsubscribePage;

  /// No description provided for @unsubscribeNone.
  ///
  /// In en, this message translates to:
  /// **'{sender} gives no way to unsubscribe. Move it to the Inbox, or archive what comes.'**
  String unsubscribeNone(String sender);

  /// No description provided for @unsubscribeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe'**
  String get unsubscribeConfirm;

  /// No description provided for @unsubscribeOpen.
  ///
  /// In en, this message translates to:
  /// **'Open page'**
  String get unsubscribeOpen;

  /// No description provided for @unsubscribeDone.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribed from {sender}'**
  String unsubscribeDone(String sender);

  /// No description provided for @unsubscribeFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t unsubscribe. Check the connection and try again.'**
  String get unsubscribeFailed;

  /// No description provided for @alwaysInInbox.
  ///
  /// In en, this message translates to:
  /// **'Always in Inbox'**
  String get alwaysInInbox;

  /// No description provided for @alwaysInInboxDone.
  ///
  /// In en, this message translates to:
  /// **'Mail from {sender} now goes to the Inbox'**
  String alwaysInInboxDone(String sender);

  /// No description provided for @newslettersArchiveNote.
  ///
  /// In en, this message translates to:
  /// **'Read more than 7 days ago? They archive themselves'**
  String get newslettersArchiveNote;

  /// No description provided for @newslettersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No newsletters'**
  String get newslettersEmpty;

  /// No description provided for @newslettersToRead.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{All read} =1{1 read} other{{count} reads}}'**
  String newslettersToRead(int count);

  /// No description provided for @newslettersMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String newslettersMinutes(int minutes);

  /// No description provided for @newslettersMinutesLong.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes in all'**
  String newslettersMinutesLong(int minutes);

  /// No description provided for @newslettersNew.
  ///
  /// In en, this message translates to:
  /// **'{count} new'**
  String newslettersNew(int count);

  /// No description provided for @folderVault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get folderVault;

  /// No description provided for @vaultTileLabel.
  ///
  /// In en, this message translates to:
  /// **'Vault, {status}'**
  String vaultTileLabel(String status);

  /// No description provided for @vaultSidebarLabel.
  ///
  /// In en, this message translates to:
  /// **'Vault, {count} waiting'**
  String vaultSidebarLabel(int count);

  /// No description provided for @vaultDue.
  ///
  /// In en, this message translates to:
  /// **'Due {when}'**
  String vaultDue(String when);

  /// No description provided for @vaultArrives.
  ///
  /// In en, this message translates to:
  /// **'Due {when}'**
  String vaultArrives(String when);

  /// No description provided for @vaultAllClear.
  ///
  /// In en, this message translates to:
  /// **'All clear'**
  String get vaultAllClear;

  /// No description provided for @vaultToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get vaultToday;

  /// No description provided for @vaultTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get vaultTomorrow;

  /// No description provided for @dayTomorrow.
  ///
  /// In en, this message translates to:
  /// **'tomorrow'**
  String get dayTomorrow;

  /// No description provided for @vaultInDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{today} =1{tomorrow} other{in {days} days}}'**
  String vaultInDays(int days);

  /// No description provided for @parcelOrdered.
  ///
  /// In en, this message translates to:
  /// **'Ordered'**
  String get parcelOrdered;

  /// No description provided for @parcelShipped.
  ///
  /// In en, this message translates to:
  /// **'Shipped'**
  String get parcelShipped;

  /// No description provided for @parcelTransit.
  ///
  /// In en, this message translates to:
  /// **'In transit'**
  String get parcelTransit;

  /// No description provided for @parcelDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get parcelDelivered;

  /// No description provided for @vaultDeliveredOn.
  ///
  /// In en, this message translates to:
  /// **'Delivered {day}'**
  String vaultDeliveredOn(String day);

  /// No description provided for @vaultCarrierFrom.
  ///
  /// In en, this message translates to:
  /// **'{carrier} · from {merchant}'**
  String vaultCarrierFrom(String carrier, String merchant);

  /// No description provided for @vaultFrom.
  ///
  /// In en, this message translates to:
  /// **'From {merchant}'**
  String vaultFrom(String merchant);

  /// No description provided for @vaultLastScan.
  ///
  /// In en, this message translates to:
  /// **'Last scan: {place}'**
  String vaultLastScan(String place);

  /// No description provided for @vaultDueLabel.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get vaultDueLabel;

  /// No description provided for @vaultPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get vaultPaid;

  /// No description provided for @vaultDownloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get vaultDownloadPdf;

  /// No description provided for @vaultMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark as paid'**
  String get vaultMarkPaid;

  /// No description provided for @vaultPaidFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save that. Try again.'**
  String get vaultPaidFailed;

  /// No description provided for @vaultFlight.
  ///
  /// In en, this message translates to:
  /// **'Flight {number} · {date}'**
  String vaultFlight(String number, String date);

  /// No description provided for @vaultCityTime.
  ///
  /// In en, this message translates to:
  /// **'{city} · {time}'**
  String vaultCityTime(String city, String time);

  /// No description provided for @vaultSeat.
  ///
  /// In en, this message translates to:
  /// **'Seat'**
  String get vaultSeat;

  /// No description provided for @vaultCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get vaultCode;

  /// No description provided for @vaultBoardingPass.
  ///
  /// In en, this message translates to:
  /// **'Boarding pass'**
  String get vaultBoardingPass;

  /// No description provided for @vaultPeople.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person} other{{count} people}}'**
  String vaultPeople(int count);

  /// No description provided for @vaultConfirmed.
  ///
  /// In en, this message translates to:
  /// **'confirmed'**
  String get vaultConfirmed;

  /// No description provided for @vaultPending.
  ///
  /// In en, this message translates to:
  /// **'to confirm'**
  String get vaultPending;

  /// No description provided for @vaultCancelled.
  ///
  /// In en, this message translates to:
  /// **'cancelled'**
  String get vaultCancelled;

  /// No description provided for @vaultDirections.
  ///
  /// In en, this message translates to:
  /// **'Directions'**
  String get vaultDirections;

  /// No description provided for @vaultNotePhone.
  ///
  /// In en, this message translates to:
  /// **'Read on-device from the original email · tap a card to open it'**
  String get vaultNotePhone;

  /// No description provided for @vaultEmpty.
  ///
  /// In en, this message translates to:
  /// **'Parcels, spending, trips and more show up here, read on this device from their emails.'**
  String get vaultEmpty;

  /// No description provided for @folderAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get folderAttachments;

  /// No description provided for @attachmentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every file you’ve received, no need to open the email'**
  String get attachmentsSubtitle;

  /// No description provided for @attachmentsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get attachmentsAll;

  /// No description provided for @attachmentsMedia.
  ///
  /// In en, this message translates to:
  /// **'Photos & media'**
  String get attachmentsMedia;

  /// No description provided for @attachmentsDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get attachmentsDocuments;

  /// No description provided for @attachmentsSheets.
  ///
  /// In en, this message translates to:
  /// **'Sheets'**
  String get attachmentsSheets;

  /// No description provided for @attachmentsFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter by type'**
  String get attachmentsFilter;

  /// No description provided for @attachmentsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search files or senders'**
  String get attachmentsSearch;

  /// No description provided for @attachmentsSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search attachments'**
  String get attachmentsSearchLabel;

  /// No description provided for @attachmentsRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get attachmentsRecent;

  /// No description provided for @attachmentsLargest.
  ///
  /// In en, this message translates to:
  /// **'Largest'**
  String get attachmentsLargest;

  /// No description provided for @attachmentsSortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort by: {sort}'**
  String attachmentsSortLabel(String sort);

  /// No description provided for @attachmentsThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get attachmentsThisWeek;

  /// No description provided for @attachmentsEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get attachmentsEarlier;

  /// No description provided for @attachmentsMeta.
  ///
  /// In en, this message translates to:
  /// **'From: {name} · {size} · {when}'**
  String attachmentsMeta(String name, String size, String when);

  /// No description provided for @attachmentsDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get attachmentsDownload;

  /// No description provided for @attachmentsOpenEmail.
  ///
  /// In en, this message translates to:
  /// **'Open email'**
  String get attachmentsOpenEmail;

  /// No description provided for @attachmentsEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get attachmentsEmail;

  /// No description provided for @attachmentsCardLabel.
  ///
  /// In en, this message translates to:
  /// **'{name}, from {from}, {size}'**
  String attachmentsCardLabel(String name, String from, String size);

  /// No description provided for @attachmentsDownloadLabel.
  ///
  /// In en, this message translates to:
  /// **'Download {name}'**
  String attachmentsDownloadLabel(String name);

  /// No description provided for @attachmentsEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Open email from {from}'**
  String attachmentsEmailLabel(String from);

  /// No description provided for @attachmentsNoneNew.
  ///
  /// In en, this message translates to:
  /// **'Nothing new'**
  String get attachmentsNoneNew;

  /// No description provided for @attachmentsTileLabel.
  ///
  /// In en, this message translates to:
  /// **'Attachments, {status}'**
  String attachmentsTileLabel(String status);

  /// No description provided for @attachmentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Files you receive show up here, from every account.'**
  String get attachmentsEmpty;

  /// No description provided for @attachmentsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No files match “{query}”'**
  String attachmentsNoMatch(String query);

  /// No description provided for @attachmentsNew.
  ///
  /// In en, this message translates to:
  /// **'{count} new'**
  String attachmentsNew(int count);

  /// No description provided for @folderSnoozed.
  ///
  /// In en, this message translates to:
  /// **'Snoozed'**
  String get folderSnoozed;

  /// No description provided for @snoozeUntilTitle.
  ///
  /// In en, this message translates to:
  /// **'Snooze until…'**
  String get snoozeUntilTitle;

  /// No description provided for @snoozeEvening.
  ///
  /// In en, this message translates to:
  /// **'This evening'**
  String get snoozeEvening;

  /// No description provided for @snoozeMorning.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow morning'**
  String get snoozeMorning;

  /// No description provided for @snoozeWeekend.
  ///
  /// In en, this message translates to:
  /// **'Weekend'**
  String get snoozeWeekend;

  /// No description provided for @snoozeNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get snoozeNextWeek;

  /// No description provided for @snoozeTileToday.
  ///
  /// In en, this message translates to:
  /// **'today {time}'**
  String snoozeTileToday(String time);

  /// No description provided for @snoozeToday.
  ///
  /// In en, this message translates to:
  /// **'today, {time}'**
  String snoozeToday(String time);

  /// No description provided for @snoozeTomorrow.
  ///
  /// In en, this message translates to:
  /// **'tomorrow, {time}'**
  String snoozeTomorrow(String time);

  /// No description provided for @snoozeTomorrowShort.
  ///
  /// In en, this message translates to:
  /// **'tomorrow {time}'**
  String snoozeTomorrowShort(String time);

  /// No description provided for @snoozedMany.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Snoozed until {when}} other{{count} conversations snoozed until {when}}}'**
  String snoozedMany(int count, String when);

  /// No description provided for @wakeNow.
  ///
  /// In en, this message translates to:
  /// **'Back to inbox'**
  String get wakeNow;

  /// No description provided for @wokenMany.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Back in the inbox} other{{count} conversations back in the inbox}}'**
  String wokenMany(int count);

  /// No description provided for @sectionTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get sectionTomorrow;

  /// No description provided for @sectionLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get sectionLater;

  /// No description provided for @sendLater.
  ///
  /// In en, this message translates to:
  /// **'Send later'**
  String get sendLater;

  /// No description provided for @sendLaterTomorrowMorning.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow morning'**
  String get sendLaterTomorrowMorning;

  /// No description provided for @sendLaterTomorrowAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow afternoon'**
  String get sendLaterTomorrowAfternoon;

  /// No description provided for @sendLaterMondayMorning.
  ///
  /// In en, this message translates to:
  /// **'Monday morning'**
  String get sendLaterMondayMorning;

  /// No description provided for @scheduleTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Schedule for tomorrow at {time}'**
  String scheduleTomorrow(String time);

  /// No description provided for @scheduleOn.
  ///
  /// In en, this message translates to:
  /// **'Schedule for {day} at {time}'**
  String scheduleOn(String day, String time);

  /// No description provided for @sendLaterNote.
  ///
  /// In en, this message translates to:
  /// **'Sent from this device at that time. If it’s off then, it goes as soon as it’s back on.'**
  String get sendLaterNote;

  /// No description provided for @scheduledToast.
  ///
  /// In en, this message translates to:
  /// **'Scheduled for {when}'**
  String scheduledToast(String when);

  /// No description provided for @paletteLabel.
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get paletteLabel;

  /// No description provided for @paletteHint.
  ///
  /// In en, this message translates to:
  /// **'Search or run a command'**
  String get paletteHint;

  /// No description provided for @paletteActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get paletteActions;

  /// No description provided for @paletteMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get paletteMessages;

  /// No description provided for @paletteWriteTo.
  ///
  /// In en, this message translates to:
  /// **'Write to {name}'**
  String paletteWriteTo(String name);

  /// No description provided for @paletteOnlyFrom.
  ///
  /// In en, this message translates to:
  /// **'Show only messages from {name}'**
  String paletteOnlyFrom(String name);

  /// No description provided for @paletteFilesFrom.
  ///
  /// In en, this message translates to:
  /// **'Attachments from {name}'**
  String paletteFilesFrom(String name);

  /// No description provided for @paletteFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String paletteFiles(int count);

  /// No description provided for @paletteSearchAll.
  ///
  /// In en, this message translates to:
  /// **'Search all mail for “{query}”'**
  String paletteSearchAll(String query);

  /// No description provided for @paletteGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to {place}'**
  String paletteGoTo(String place);

  /// No description provided for @paletteMove.
  ///
  /// In en, this message translates to:
  /// **'move'**
  String get paletteMove;

  /// No description provided for @paletteRun.
  ///
  /// In en, this message translates to:
  /// **'run'**
  String get paletteRun;

  /// No description provided for @paletteAnywhere.
  ///
  /// In en, this message translates to:
  /// **'from any screen'**
  String get paletteAnywhere;

  /// No description provided for @senderCardLabel.
  ///
  /// In en, this message translates to:
  /// **'{name}’s card'**
  String senderCardLabel(String name);

  /// No description provided for @senderKind.
  ///
  /// In en, this message translates to:
  /// **'Sender'**
  String get senderKind;

  /// No description provided for @senderClose.
  ///
  /// In en, this message translates to:
  /// **'Close card'**
  String get senderClose;

  /// No description provided for @senderWrite.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get senderWrite;

  /// No description provided for @senderAll.
  ///
  /// In en, this message translates to:
  /// **'All emails'**
  String get senderAll;

  /// No description provided for @senderMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get senderMute;

  /// No description provided for @senderMuted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get senderMuted;

  /// No description provided for @senderArrivesIn.
  ///
  /// In en, this message translates to:
  /// **'Arrives in {account}'**
  String senderArrivesIn(String account);

  /// No description provided for @senderConversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get senderConversations;

  /// No description provided for @senderNoMail.
  ///
  /// In en, this message translates to:
  /// **'No emails from them on this device yet.'**
  String get senderNoMail;

  /// No description provided for @senderMutedToast.
  ///
  /// In en, this message translates to:
  /// **'No more notifications from {name}'**
  String senderMutedToast(String name);

  /// No description provided for @rulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Rules & folders'**
  String get rulesTitle;

  /// No description provided for @rulesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sorts your mail the way you would. Every rule reads like a sentence.'**
  String get rulesSubtitle;

  /// No description provided for @rulesWhere.
  ///
  /// In en, this message translates to:
  /// **'Rules run on this device, on new mail in the inbox'**
  String get rulesWhere;

  /// No description provided for @rulesHeading.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get rulesHeading;

  /// No description provided for @rulesNew.
  ///
  /// In en, this message translates to:
  /// **'New rule'**
  String get rulesNew;

  /// No description provided for @rulesEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit rule'**
  String get rulesEdit;

  /// No description provided for @rulesNone.
  ///
  /// In en, this message translates to:
  /// **'No rules of your own yet. A rule sorts new mail as it lands, the way you would.'**
  String get rulesNone;

  /// No description provided for @ruleWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get ruleWhen;

  /// No description provided for @ruleThen.
  ///
  /// In en, this message translates to:
  /// **'then'**
  String get ruleThen;

  /// No description provided for @ruleFieldSender.
  ///
  /// In en, this message translates to:
  /// **'the sender'**
  String get ruleFieldSender;

  /// No description provided for @ruleFieldSubject.
  ///
  /// In en, this message translates to:
  /// **'the subject'**
  String get ruleFieldSubject;

  /// No description provided for @ruleFieldRecipient.
  ///
  /// In en, this message translates to:
  /// **'the recipient'**
  String get ruleFieldRecipient;

  /// No description provided for @ruleOpContains.
  ///
  /// In en, this message translates to:
  /// **'contains'**
  String get ruleOpContains;

  /// No description provided for @ruleOpIs.
  ///
  /// In en, this message translates to:
  /// **'is'**
  String get ruleOpIs;

  /// No description provided for @ruleOpStarts.
  ///
  /// In en, this message translates to:
  /// **'starts with'**
  String get ruleOpStarts;

  /// No description provided for @ruleOpNotContains.
  ///
  /// In en, this message translates to:
  /// **'doesn’t contain'**
  String get ruleOpNotContains;

  /// No description provided for @ruleDoMove.
  ///
  /// In en, this message translates to:
  /// **'move to'**
  String get ruleDoMove;

  /// No description provided for @ruleDoArchive.
  ///
  /// In en, this message translates to:
  /// **'archive'**
  String get ruleDoArchive;

  /// No description provided for @ruleDoRead.
  ///
  /// In en, this message translates to:
  /// **'mark as read'**
  String get ruleDoRead;

  /// No description provided for @ruleText.
  ///
  /// In en, this message translates to:
  /// **'Text to match'**
  String get ruleText;

  /// No description provided for @ruleTextHint.
  ///
  /// In en, this message translates to:
  /// **'text'**
  String get ruleTextHint;

  /// No description provided for @ruleTrayField.
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get ruleTrayField;

  /// No description provided for @ruleTrayOp.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get ruleTrayOp;

  /// No description provided for @ruleTrayAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get ruleTrayAction;

  /// No description provided for @ruleTrayFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get ruleTrayFolder;

  /// No description provided for @rulePickFolder.
  ///
  /// In en, this message translates to:
  /// **'a folder'**
  String get rulePickFolder;

  /// No description provided for @ruleNoFolders.
  ///
  /// In en, this message translates to:
  /// **'Your accounts have no folders of their own yet.'**
  String get ruleNoFolders;

  /// No description provided for @ruleApplyToo.
  ///
  /// In en, this message translates to:
  /// **'Apply to those too'**
  String get ruleApplyToo;

  /// No description provided for @ruleSave.
  ///
  /// In en, this message translates to:
  /// **'Save rule'**
  String get ruleSave;

  /// No description provided for @ruleDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete rule'**
  String get ruleDelete;

  /// No description provided for @rulePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get rulePaused;

  /// No description provided for @ruleFresh.
  ///
  /// In en, this message translates to:
  /// **'Active from now'**
  String get ruleFresh;

  /// No description provided for @foldersHeading.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get foldersHeading;

  /// No description provided for @foldersNone.
  ///
  /// In en, this message translates to:
  /// **'No folders of its own'**
  String get foldersNone;

  /// No description provided for @ruleApplies.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No existing emails match} =1{Applies to {count} existing email} other{Applies to {count} existing emails}}'**
  String ruleApplies(int count);

  /// No description provided for @ruleSorted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 email sorted} other{{count} emails sorted}}'**
  String ruleSorted(int count);

  /// No description provided for @ruleLastToday.
  ///
  /// In en, this message translates to:
  /// **'last today {time}'**
  String ruleLastToday(String time);

  /// No description provided for @ruleLastOn.
  ///
  /// In en, this message translates to:
  /// **'last {date}'**
  String ruleLastOn(String date);

  /// No description provided for @ruleSwitch.
  ///
  /// In en, this message translates to:
  /// **'Rule on: {rule}'**
  String ruleSwitch(String rule);

  /// No description provided for @rulesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None} other{{count}}}'**
  String rulesCount(int count);

  /// No description provided for @inviteLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get inviteLabel;

  /// No description provided for @inviteYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get inviteYes;

  /// No description provided for @inviteMaybe.
  ///
  /// In en, this message translates to:
  /// **'Maybe'**
  String get inviteMaybe;

  /// No description provided for @inviteNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get inviteNo;

  /// No description provided for @inviteRespond.
  ///
  /// In en, this message translates to:
  /// **'Respond to invite'**
  String get inviteRespond;

  /// No description provided for @inviteAllDay.
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get inviteAllDay;

  /// No description provided for @inviteRepeats.
  ///
  /// In en, this message translates to:
  /// **'repeats'**
  String get inviteRepeats;

  /// No description provided for @inviteYouAccepted.
  ///
  /// In en, this message translates to:
  /// **'You accepted'**
  String get inviteYouAccepted;

  /// No description provided for @inviteYouTentative.
  ///
  /// In en, this message translates to:
  /// **'You replied maybe'**
  String get inviteYouTentative;

  /// No description provided for @inviteYouDeclined.
  ///
  /// In en, this message translates to:
  /// **'You declined'**
  String get inviteYouDeclined;

  /// No description provided for @inviteNotSent.
  ///
  /// In en, this message translates to:
  /// **'Your reply couldn’t be sent. Try again.'**
  String get inviteNotSent;

  /// No description provided for @inviteCancelled.
  ///
  /// In en, this message translates to:
  /// **'This event was cancelled'**
  String get inviteCancelled;

  /// No description provided for @inviteYours.
  ///
  /// In en, this message translates to:
  /// **'You sent this invite'**
  String get inviteYours;

  /// No description provided for @inviteAttendees.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attendee} other{{count} attendees}}'**
  String inviteAttendees(int count);

  /// No description provided for @inviteWillGet.
  ///
  /// In en, this message translates to:
  /// **'{name} will get your reply'**
  String inviteWillGet(String name);

  /// No description provided for @inviteQueued.
  ///
  /// In en, this message translates to:
  /// **'goes to {name} when you’re back online'**
  String inviteQueued(String name);

  /// No description provided for @inviteTheyAccepted.
  ///
  /// In en, this message translates to:
  /// **'{name} accepted'**
  String inviteTheyAccepted(String name);

  /// No description provided for @inviteTheyTentative.
  ///
  /// In en, this message translates to:
  /// **'{name} replied maybe'**
  String inviteTheyTentative(String name);

  /// No description provided for @inviteTheyDeclined.
  ///
  /// In en, this message translates to:
  /// **'{name} declined'**
  String inviteTheyDeclined(String name);

  /// No description provided for @inviteSubjectAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted: {summary}'**
  String inviteSubjectAccepted(String summary);

  /// No description provided for @inviteSubjectTentative.
  ///
  /// In en, this message translates to:
  /// **'Maybe: {summary}'**
  String inviteSubjectTentative(String summary);

  /// No description provided for @inviteSubjectDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined: {summary}'**
  String inviteSubjectDeclined(String summary);

  /// No description provided for @inviteTextAccepted.
  ///
  /// In en, this message translates to:
  /// **'{name} accepted this invitation.'**
  String inviteTextAccepted(String name);

  /// No description provided for @inviteTextTentative.
  ///
  /// In en, this message translates to:
  /// **'{name} might come.'**
  String inviteTextTentative(String name);

  /// No description provided for @inviteTextDeclined.
  ///
  /// In en, this message translates to:
  /// **'{name} declined this invitation.'**
  String inviteTextDeclined(String name);

  /// No description provided for @inviteCard.
  ///
  /// In en, this message translates to:
  /// **'Invite: {summary}, {when}'**
  String inviteCard(String summary, String when);

  /// No description provided for @inviteFree.
  ///
  /// In en, this message translates to:
  /// **'Free · no conflicts'**
  String get inviteFree;

  /// No description provided for @inviteOverlaps.
  ///
  /// In en, this message translates to:
  /// **'Overlaps {name} {time}'**
  String inviteOverlaps(String name, String time);

  /// No description provided for @inviteAvailability.
  ///
  /// In en, this message translates to:
  /// **'Availability: {note}'**
  String inviteAvailability(String note);

  /// No description provided for @inviteAddedTo.
  ///
  /// In en, this message translates to:
  /// **'added to {name}'**
  String inviteAddedTo(String name);

  /// No description provided for @settingsCalendars.
  ///
  /// In en, this message translates to:
  /// **'Calendars'**
  String get settingsCalendars;

  /// No description provided for @calIntro.
  ///
  /// In en, this message translates to:
  /// **'Piuma has no calendar of its own: connect the ones you already use. Events stay there.'**
  String get calIntro;

  /// No description provided for @calConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected calendars'**
  String get calConnected;

  /// No description provided for @calSources.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 source} other{{count} sources}}'**
  String calSources(int count);

  /// No description provided for @calCalendars.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 calendar} other{{count} calendars}}'**
  String calCalendars(int count);

  /// No description provided for @calConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect a calendar'**
  String get calConnect;

  /// No description provided for @calChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose where to connect from'**
  String get calChoose;

  /// No description provided for @calCalDav.
  ///
  /// In en, this message translates to:
  /// **'CalDAV'**
  String get calCalDav;

  /// No description provided for @calCalDavParen.
  ///
  /// In en, this message translates to:
  /// **'(iCloud, Fastmail, Nextcloud…)'**
  String get calCalDavParen;

  /// No description provided for @calCalDavSub.
  ///
  /// In en, this message translates to:
  /// **'Server, email and app password'**
  String get calCalDavSub;

  /// No description provided for @calIcs.
  ///
  /// In en, this message translates to:
  /// **'Subscribe to an .ics URL'**
  String get calIcs;

  /// No description provided for @calIcsSub.
  ///
  /// In en, this message translates to:
  /// **'Read-only, updates on its own'**
  String get calIcsSub;

  /// No description provided for @calCalDavLabel.
  ///
  /// In en, this message translates to:
  /// **'Email address or CalDAV server'**
  String get calCalDavLabel;

  /// No description provided for @calCalDavHint.
  ///
  /// In en, this message translates to:
  /// **'iCloud needs an app password; it stays encrypted in the system keychain.'**
  String get calCalDavHint;

  /// No description provided for @calIcsLabel.
  ///
  /// In en, this message translates to:
  /// **'.ics calendar URL'**
  String get calIcsLabel;

  /// No description provided for @calIcsHint.
  ///
  /// In en, this message translates to:
  /// **'.ics calendars are read-only: handy for holidays, sports, shifts.'**
  String get calIcsHint;

  /// No description provided for @calUsername.
  ///
  /// In en, this message translates to:
  /// **'User name (if not the email)'**
  String get calUsername;

  /// No description provided for @calPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get calPassword;

  /// No description provided for @calConnectButton.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get calConnectButton;

  /// No description provided for @calSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get calSubscribe;

  /// No description provided for @calSuggested.
  ///
  /// In en, this message translates to:
  /// **'Email accounts you’ve added that offer a calendar are suggested automatically'**
  String get calSuggested;

  /// No description provided for @calHasCalendar.
  ///
  /// In en, this message translates to:
  /// **'has a calendar too'**
  String get calHasCalendar;

  /// No description provided for @calDone.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get calDone;

  /// No description provided for @calDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get calDisconnect;

  /// No description provided for @calDisconnectLabel.
  ///
  /// In en, this message translates to:
  /// **'Disconnect {name}'**
  String calDisconnectLabel(String name);

  /// No description provided for @calReadOnly.
  ///
  /// In en, this message translates to:
  /// **'read-only'**
  String get calReadOnly;

  /// No description provided for @calInvitesTag.
  ///
  /// In en, this message translates to:
  /// **'invites'**
  String get calInvitesTag;

  /// No description provided for @calShowAvailability.
  ///
  /// In en, this message translates to:
  /// **'Show availability'**
  String get calShowAvailability;

  /// No description provided for @calAvailabilityShort.
  ///
  /// In en, this message translates to:
  /// **'availability'**
  String get calAvailabilityShort;

  /// No description provided for @calAvailabilityFor.
  ///
  /// In en, this message translates to:
  /// **'Show availability for {name}'**
  String calAvailabilityFor(String name);

  /// No description provided for @calNone.
  ///
  /// In en, this message translates to:
  /// **'No calendars connected. Invites still work, via email.'**
  String get calNone;

  /// No description provided for @calWhenInvite.
  ///
  /// In en, this message translates to:
  /// **'When an invite arrives'**
  String get calWhenInvite;

  /// No description provided for @calAddTo.
  ///
  /// In en, this message translates to:
  /// **'Add to'**
  String get calAddTo;

  /// No description provided for @calAddToSub.
  ///
  /// In en, this message translates to:
  /// **'Where invites you accept go'**
  String get calAddToSub;

  /// No description provided for @calAddInvitesTo.
  ///
  /// In en, this message translates to:
  /// **'Add invites to'**
  String get calAddInvitesTo;

  /// No description provided for @calNoWritable.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get calNoWritable;

  /// No description provided for @calConflicts.
  ///
  /// In en, this message translates to:
  /// **'Check for conflicts across all connected calendars'**
  String get calConflicts;

  /// No description provided for @calConflictsSub.
  ///
  /// In en, this message translates to:
  /// **'Invites show right away if you’re already busy then.'**
  String get calConflictsSub;

  /// No description provided for @calFooter.
  ///
  /// In en, this message translates to:
  /// **'Without connected calendars you can still answer invites by email and open the .ics file.'**
  String get calFooter;

  /// No description provided for @calStaysHere.
  ///
  /// In en, this message translates to:
  /// **'Connections stay on this device; passwords are kept in the system keychain.'**
  String get calStaysHere;

  /// No description provided for @calWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong user name or password.'**
  String get calWrongPassword;

  /// No description provided for @calUnreachable.
  ///
  /// In en, this message translates to:
  /// **'No calendar found there. Check the address.'**
  String get calUnreachable;

  /// No description provided for @calFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t connect. Try again.'**
  String get calFailed;

  /// No description provided for @calTypeCalDav.
  ///
  /// In en, this message translates to:
  /// **'CalDAV'**
  String get calTypeCalDav;

  /// No description provided for @calTypeIcs.
  ///
  /// In en, this message translates to:
  /// **'.ics URL, read-only'**
  String get calTypeIcs;

  /// No description provided for @calFromAccount.
  ///
  /// In en, this message translates to:
  /// **'from the email account'**
  String get calFromAccount;

  /// No description provided for @foundDateAdd.
  ///
  /// In en, this message translates to:
  /// **'Add {when} to calendar'**
  String foundDateAdd(String when);

  /// No description provided for @foundDateAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to {calendar}'**
  String foundDateAdded(String calendar);

  /// No description provided for @foundDateAddLabel.
  ///
  /// In en, this message translates to:
  /// **'Add {when} to calendar, found on this device'**
  String foundDateAddLabel(String when);

  /// No description provided for @foundDateAddedLabel.
  ///
  /// In en, this message translates to:
  /// **'{when} added to {calendar}'**
  String foundDateAddedLabel(String when, String calendar);

  /// No description provided for @foundOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Found on this device'**
  String get foundOnDevice;

  /// No description provided for @foundDateNotAdded.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t add it to the calendar. Try again in a moment.'**
  String get foundDateNotAdded;

  /// No description provided for @calFindDates.
  ///
  /// In en, this message translates to:
  /// **'Suggest adding dates found in emails'**
  String get calFindDates;

  /// No description provided for @calFindDatesSub.
  ///
  /// In en, this message translates to:
  /// **'A small suggestion next to the sentence, never automatic.'**
  String get calFindDatesSub;

  /// No description provided for @calOnDevice.
  ///
  /// In en, this message translates to:
  /// **'on-device'**
  String get calOnDevice;

  /// No description provided for @inShort.
  ///
  /// In en, this message translates to:
  /// **'In short'**
  String get inShort;

  /// No description provided for @generatedOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Generated on device'**
  String get generatedOnDevice;

  /// No description provided for @yourTurn.
  ///
  /// In en, this message translates to:
  /// **'Your turn:'**
  String get yourTurn;

  /// No description provided for @yourTurnAsks.
  ///
  /// In en, this message translates to:
  /// **'{name} writes “{words}”'**
  String yourTurnAsks(String name, String words);

  /// No description provided for @inShortColon.
  ///
  /// In en, this message translates to:
  /// **'In short:'**
  String get inShortColon;

  /// No description provided for @onDevice.
  ///
  /// In en, this message translates to:
  /// **'on device'**
  String get onDevice;

  /// No description provided for @senderBriefTopic.
  ///
  /// In en, this message translates to:
  /// **'mostly about “{topic}”'**
  String senderBriefTopic(String topic);

  /// No description provided for @senderBriefCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 email this month} other{{count} emails this month}}'**
  String senderBriefCount(int count);

  /// No description provided for @senderBriefWaiting.
  ///
  /// In en, this message translates to:
  /// **'the latest is waiting on your reply'**
  String get senderBriefWaiting;

  /// No description provided for @searchByType.
  ///
  /// In en, this message translates to:
  /// **'Search by type'**
  String get searchByType;

  /// No description provided for @frequentContacts.
  ///
  /// In en, this message translates to:
  /// **'Frequent contacts'**
  String get frequentContacts;

  /// No description provided for @recentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// No description provided for @clearRecent.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearRecent;

  /// No description provided for @clearRecentSearches.
  ///
  /// In en, this message translates to:
  /// **'Clear recent searches'**
  String get clearRecentSearches;

  /// No description provided for @noRecentSearches.
  ///
  /// In en, this message translates to:
  /// **'No recent searches.'**
  String get noRecentSearches;

  /// No description provided for @searchOperatorsHint.
  ///
  /// In en, this message translates to:
  /// **'You can also type operators'**
  String get searchOperatorsHint;

  /// No description provided for @searchIndexed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 email indexed on this device · works offline} other{{formatted} emails indexed on this device · works offline}}'**
  String searchIndexed(int count, String formatted);

  /// No description provided for @searchWithAttachments.
  ///
  /// In en, this message translates to:
  /// **'With attachments'**
  String get searchWithAttachments;

  /// No description provided for @searchFromPeople.
  ///
  /// In en, this message translates to:
  /// **'From people'**
  String get searchFromPeople;

  /// No description provided for @searchMailFrom.
  ///
  /// In en, this message translates to:
  /// **'Search mail from {name}'**
  String searchMailFrom(String name);

  /// No description provided for @removeRecentSearch.
  ///
  /// In en, this message translates to:
  /// **'Remove {query}'**
  String removeRecentSearch(String query);

  /// No description provided for @searchAddWords.
  ///
  /// In en, this message translates to:
  /// **'Add words…'**
  String get searchAddWords;

  /// No description provided for @rowPhotos.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String rowPhotos(int count);

  /// No description provided for @rowAttachments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attachment} other{{count} attachments}}'**
  String rowAttachments(int count);

  /// No description provided for @senderBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get senderBlock;

  /// No description provided for @senderBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get senderBlocked;

  /// No description provided for @showSnoozed.
  ///
  /// In en, this message translates to:
  /// **'Show Snoozed ({count})'**
  String showSnoozed(int count);

  /// No description provided for @hideSnoozed.
  ///
  /// In en, this message translates to:
  /// **'Hide Snoozed'**
  String get hideSnoozed;

  /// No description provided for @snoozeNoReply.
  ///
  /// In en, this message translates to:
  /// **'If nobody replies'**
  String get snoozeNoReply;

  /// No description provided for @snoozeNoReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Comes back in 3 days if there’s no reply'**
  String get snoozeNoReplyHint;

  /// No description provided for @previewClose.
  ///
  /// In en, this message translates to:
  /// **'Close preview'**
  String get previewClose;

  /// No description provided for @previewMeta.
  ///
  /// In en, this message translates to:
  /// **'{size} · from {name}'**
  String previewMeta(String size, String name);

  /// No description provided for @previewPage.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {count}'**
  String previewPage(int page, int count);

  /// No description provided for @previewPrevPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get previewPrevPage;

  /// No description provided for @previewNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get previewNextPage;

  /// No description provided for @previewOpenEmail.
  ///
  /// In en, this message translates to:
  /// **'Open {name}’s email'**
  String previewOpenEmail(String name);

  /// No description provided for @previewDownloadAll.
  ///
  /// In en, this message translates to:
  /// **'Download all'**
  String get previewDownloadAll;

  /// No description provided for @previewPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo {index} of {count} · from the same email'**
  String previewPhoto(int index, int count);

  /// No description provided for @previewPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos in the email'**
  String get previewPhotos;

  /// No description provided for @previewCantShow.
  ///
  /// In en, this message translates to:
  /// **'This file can’t be shown here. You can still download it.'**
  String get previewCantShow;

  /// No description provided for @previewPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {name}'**
  String previewPageLabel(int page, String name);

  /// No description provided for @vaultParcelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Package deliveries'**
  String get vaultParcelsTitle;

  /// No description provided for @vaultParcelsHint.
  ///
  /// In en, this message translates to:
  /// **'On delivery day, just once.'**
  String get vaultParcelsHint;

  /// No description provided for @vaultDueTitle.
  ///
  /// In en, this message translates to:
  /// **'Due dates'**
  String get vaultDueTitle;

  /// No description provided for @vaultDueHint.
  ///
  /// In en, this message translates to:
  /// **'Bills and renewals, three days ahead.'**
  String get vaultDueHint;

  /// No description provided for @vaultNoticeParcel.
  ///
  /// In en, this message translates to:
  /// **'Your package arrives today'**
  String get vaultNoticeParcel;

  /// No description provided for @vaultNoticeDueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get vaultNoticeDueToday;

  /// No description provided for @vaultNoticeDueTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Due tomorrow'**
  String get vaultNoticeDueTomorrow;

  /// No description provided for @vaultNoticeDueIn.
  ///
  /// In en, this message translates to:
  /// **'Due in {days} days'**
  String vaultNoticeDueIn(int days);

  /// No description provided for @vaultNoticeAround.
  ///
  /// In en, this message translates to:
  /// **'around {time}'**
  String vaultNoticeAround(String time);

  /// No description provided for @pecCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 certified email} other{{count} certified emails}}'**
  String pecCount(int count);

  /// No description provided for @pecNotDelivered.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} not delivered}}'**
  String pecNotDelivered(int count);

  /// No description provided for @pecSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get pecSent;

  /// No description provided for @pecAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get pecAccepted;

  /// No description provided for @pecDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get pecDelivered;

  /// No description provided for @pecFailed.
  ///
  /// In en, this message translates to:
  /// **'Not delivered'**
  String get pecFailed;

  /// No description provided for @pecTo.
  ///
  /// In en, this message translates to:
  /// **'To {who}'**
  String pecTo(String who);

  /// No description provided for @pecToMany.
  ///
  /// In en, this message translates to:
  /// **'To {count} recipients · {delivered} of {count} delivered'**
  String pecToMany(int count, int delivered);

  /// No description provided for @pecAcceptedAt.
  ///
  /// In en, this message translates to:
  /// **'Accepted {when}'**
  String pecAcceptedAt(String when);

  /// No description provided for @pecDeliveredAt.
  ///
  /// In en, this message translates to:
  /// **'Delivered {when}'**
  String pecDeliveredAt(String when);

  /// No description provided for @pecFailedAt.
  ///
  /// In en, this message translates to:
  /// **'Not delivered · {when}'**
  String pecFailedAt(String when);

  /// No description provided for @pecReasonAt.
  ///
  /// In en, this message translates to:
  /// **'{reason} · {when}'**
  String pecReasonAt(String reason, String when);

  /// No description provided for @pecOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get pecOpen;

  /// No description provided for @pecReceipt.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Receipt} other{Receipts}}'**
  String pecReceipt(int count);

  /// No description provided for @pecSaved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Receipt saved in Downloads} other{{count} receipts saved in Downloads}}'**
  String pecSaved(int count);

  /// No description provided for @pecNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the receipt'**
  String get pecNotSaved;

  /// No description provided for @pecNote.
  ///
  /// In en, this message translates to:
  /// **'Receipts stay out of the inbox and gather on the message they belong to. Receipt saves the signed proof as a file.'**
  String get pecNote;

  /// No description provided for @pickDateTime.
  ///
  /// In en, this message translates to:
  /// **'Pick date & time'**
  String get pickDateTime;

  /// No description provided for @previousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get previousMonth;

  /// No description provided for @nextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get nextMonth;

  /// No description provided for @pickTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get pickTime;

  /// No description provided for @pickOtherTime.
  ///
  /// In en, this message translates to:
  /// **'Other time'**
  String get pickOtherTime;

  /// No description provided for @pickTimeGone.
  ///
  /// In en, this message translates to:
  /// **'That time has already gone by'**
  String get pickTimeGone;

  /// No description provided for @snoozeUntilAt.
  ///
  /// In en, this message translates to:
  /// **'Snooze until {when}'**
  String snoozeUntilAt(String when);

  /// No description provided for @scheduleAt.
  ///
  /// In en, this message translates to:
  /// **'Schedule for {when}'**
  String scheduleAt(String when);

  /// No description provided for @senderNewsletterKind.
  ///
  /// In en, this message translates to:
  /// **'Newsletter'**
  String get senderNewsletterKind;

  /// No description provided for @newsletterPerWeek.
  ///
  /// In en, this message translates to:
  /// **'about {count} a week'**
  String newsletterPerWeek(int count);

  /// No description provided for @newsletterPerMonth.
  ///
  /// In en, this message translates to:
  /// **'about {count} a month'**
  String newsletterPerMonth(int count);

  /// No description provided for @newsletterOpened.
  ///
  /// In en, this message translates to:
  /// **'you open {percent}%'**
  String newsletterOpened(int percent);

  /// No description provided for @newsletterUnsubscribed.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribed'**
  String get newsletterUnsubscribed;

  /// No description provided for @newsletterClearAsk.
  ///
  /// In en, this message translates to:
  /// **'clear old emails too?'**
  String get newsletterClearAsk;

  /// No description provided for @newsletterClearYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, clear'**
  String get newsletterClearYes;

  /// No description provided for @newsletterClearNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get newsletterClearNo;

  /// No description provided for @newsletterCleared.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Unsubscribed · 1 email moved to Trash} other{Unsubscribed · {count} emails moved to Trash}}'**
  String newsletterCleared(int count);

  /// No description provided for @newsletterKept.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribed · old emails stay as they are'**
  String get newsletterKept;

  /// No description provided for @newsletterPageOpened.
  ///
  /// In en, this message translates to:
  /// **'Their unsubscribe page is open in the browser'**
  String get newsletterPageOpened;

  /// No description provided for @moveToNewsletters.
  ///
  /// In en, this message translates to:
  /// **'Move to Newsletters'**
  String get moveToNewsletters;

  /// No description provided for @movedToNewsletters.
  ///
  /// In en, this message translates to:
  /// **'Moved to Newsletters'**
  String get movedToNewsletters;

  /// No description provided for @searchFileMeta.
  ///
  /// In en, this message translates to:
  /// **'{size} · {name} · {when}'**
  String searchFileMeta(String size, String name, String when);

  /// No description provided for @searchHasFiles.
  ///
  /// In en, this message translates to:
  /// **'Has attachment'**
  String get searchHasFiles;

  /// No description provided for @appearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceTitle;

  /// No description provided for @appearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How you want your mail to look.'**
  String get appearanceSubtitle;

  /// No description provided for @appearanceTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get appearanceTheme;

  /// No description provided for @themeAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get themeAutomatic;

  /// No description provided for @appearanceDensity.
  ///
  /// In en, this message translates to:
  /// **'Density'**
  String get appearanceDensity;

  /// No description provided for @densityComfortable.
  ///
  /// In en, this message translates to:
  /// **'Comfortable'**
  String get densityComfortable;

  /// No description provided for @densityCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get densityCompact;

  /// No description provided for @appearancePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get appearancePreview;

  /// No description provided for @previewLines.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line} other{{count} lines}}'**
  String previewLines(int count);

  /// No description provided for @appearanceExample.
  ///
  /// In en, this message translates to:
  /// **'Example'**
  String get appearanceExample;

  /// No description provided for @previewDrawnHere.
  ///
  /// In en, this message translates to:
  /// **'Drawn on this device'**
  String get previewDrawnHere;

  /// No description provided for @previewKeysPages.
  ///
  /// In en, this message translates to:
  /// **'← → pages'**
  String get previewKeysPages;

  /// No description provided for @previewKeysPhotos.
  ///
  /// In en, this message translates to:
  /// **'← → photos'**
  String get previewKeysPhotos;

  /// No description provided for @meInitials.
  ///
  /// In en, this message translates to:
  /// **'ME'**
  String get meInitials;

  /// No description provided for @threadSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get threadSummary;

  /// No description provided for @signatureSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get signatureSheetTitle;

  /// No description provided for @signatureManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get signatureManage;

  /// No description provided for @signatureSheetNote.
  ///
  /// In en, this message translates to:
  /// **'The signature switches automatically when you change the “From” account.'**
  String get signatureSheetNote;

  /// No description provided for @readerEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No conversation selected'**
  String get readerEmptyTitle;

  /// No description provided for @readerEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Click a message to select it, or press {keys} to select them all.'**
  String readerEmptyHint(String keys);

  /// No description provided for @hintMove.
  ///
  /// In en, this message translates to:
  /// **'move'**
  String get hintMove;

  /// No description provided for @accountConnected.
  ///
  /// In en, this message translates to:
  /// **'Account connected'**
  String get accountConnected;

  /// No description provided for @accountConnectedLead.
  ///
  /// In en, this message translates to:
  /// **'You can start reading now: the rest arrives while you use Piuma.'**
  String get accountConnectedLead;

  /// No description provided for @connectedDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading, newest first…'**
  String get connectedDownloading;

  /// No description provided for @connectedUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get connectedUpToDate;

  /// No description provided for @goToInbox.
  ///
  /// In en, this message translates to:
  /// **'Go to inbox'**
  String get goToInbox;

  /// No description provided for @addAnotherAccount.
  ///
  /// In en, this message translates to:
  /// **'Add another account'**
  String get addAnotherAccount;

  /// No description provided for @filterFrom.
  ///
  /// In en, this message translates to:
  /// **'From: {name}'**
  String filterFrom(String name);

  /// No description provided for @syncLeftUnderMinute.
  ///
  /// In en, this message translates to:
  /// **'under a minute'**
  String get syncLeftUnderMinute;

  /// No description provided for @syncLeftMinutes.
  ///
  /// In en, this message translates to:
  /// **'about {n} min'**
  String syncLeftMinutes(int n);

  /// No description provided for @syncLeftHours.
  ///
  /// In en, this message translates to:
  /// **'about {n} h'**
  String syncLeftHours(int n);

  /// No description provided for @phoneSearchSyncing.
  ///
  /// In en, this message translates to:
  /// **'{hint} · {name} syncing'**
  String phoneSearchSyncing(String hint, String name);

  /// No description provided for @sendTomorrowAt.
  ///
  /// In en, this message translates to:
  /// **'Send tomorrow {time}'**
  String sendTomorrowAt(String time);

  /// No description provided for @inboxSections.
  ///
  /// In en, this message translates to:
  /// **'Inbox sections'**
  String get inboxSections;

  /// No description provided for @tabPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get tabPeople;

  /// No description provided for @tabNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get tabNotifications;

  /// No description provided for @zoneNothingNew.
  ///
  /// In en, this message translates to:
  /// **'Nothing new'**
  String get zoneNothingNew;

  /// No description provided for @tabAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tabAll;

  /// No description provided for @filterUnreadHint.
  ///
  /// In en, this message translates to:
  /// **'Only emails with something unread'**
  String get filterUnreadHint;

  /// No description provided for @moveToPeople.
  ///
  /// In en, this message translates to:
  /// **'Move to People'**
  String get moveToPeople;

  /// No description provided for @movedToPeople.
  ///
  /// In en, this message translates to:
  /// **'{sender} goes to People from now on'**
  String movedToPeople(String sender);

  /// No description provided for @movedToNotifications.
  ///
  /// In en, this message translates to:
  /// **'{sender} goes to Notifications from now on'**
  String movedToNotifications(String sender);

  /// No description provided for @moveToNotifications.
  ///
  /// In en, this message translates to:
  /// **'Move to Notifications'**
  String get moveToNotifications;

  /// No description provided for @tabUnread.
  ///
  /// In en, this message translates to:
  /// **'{tab}, {count} unread'**
  String tabUnread(String tab, int count);

  /// No description provided for @templatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templatesTitle;

  /// No description provided for @templatesSearch.
  ///
  /// In en, this message translates to:
  /// **'Search templates'**
  String get templatesSearch;

  /// No description provided for @templatesFound.
  ///
  /// In en, this message translates to:
  /// **'{found} of {total}'**
  String templatesFound(int found, int total);

  /// No description provided for @templatesNone.
  ///
  /// In en, this message translates to:
  /// **'No templates yet. Save what you write as one.'**
  String get templatesNone;

  /// No description provided for @templatesNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No template called “{query}”'**
  String templatesNoMatch(String query);

  /// No description provided for @templateSaveThis.
  ///
  /// In en, this message translates to:
  /// **'Save as template'**
  String get templateSaveThis;

  /// No description provided for @templatesManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get templatesManage;

  /// No description provided for @templateUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled template'**
  String get templateUntitled;

  /// No description provided for @templateSavedNote.
  ///
  /// In en, this message translates to:
  /// **'Saved as template “{name}”'**
  String templateSavedNote(String name);

  /// No description provided for @templatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'On this device, for every account'**
  String get templatesSubtitle;

  /// No description provided for @templatesNew.
  ///
  /// In en, this message translates to:
  /// **'New template'**
  String get templatesNew;

  /// No description provided for @templateNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get templateNameLabel;

  /// No description provided for @templateTextLabel.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get templateTextLabel;

  /// No description provided for @templateSubjectLine.
  ///
  /// In en, this message translates to:
  /// **'Subject: {subject}'**
  String templateSubjectLine(String subject);

  /// No description provided for @templateNoSubject.
  ///
  /// In en, this message translates to:
  /// **'No subject'**
  String get templateNoSubject;

  /// No description provided for @templateSavedAsYouType.
  ///
  /// In en, this message translates to:
  /// **'Saved as you type'**
  String get templateSavedAsYouType;

  /// No description provided for @templateNotSaved.
  ///
  /// In en, this message translates to:
  /// **'The template could not be saved'**
  String get templateNotSaved;

  /// No description provided for @accountNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get accountNameLabel;

  /// No description provided for @accountDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get accountDisplayName;

  /// No description provided for @accountDisplayNameNone.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get accountDisplayNameNone;

  /// No description provided for @accountDefaultSignature.
  ///
  /// In en, this message translates to:
  /// **'Default signature'**
  String get accountDefaultSignature;

  /// No description provided for @accountConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get accountConnection;

  /// No description provided for @accountWorkingAgo.
  ///
  /// In en, this message translates to:
  /// **'Working · checked {ago}'**
  String accountWorkingAgo(String ago);

  /// No description provided for @accountJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get accountJustNow;

  /// No description provided for @accountMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String accountMinutesAgo(int count);

  /// No description provided for @accountAtTime.
  ///
  /// In en, this message translates to:
  /// **'at {time}'**
  String accountAtTime(String time);

  /// No description provided for @accountConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get accountConnecting;

  /// No description provided for @accountCantSignInSince.
  ///
  /// In en, this message translates to:
  /// **'Can\'t sign in since {time}'**
  String accountCantSignInSince(String time);

  /// No description provided for @accountPasswordRefused.
  ///
  /// In en, this message translates to:
  /// **'The server refused the password. Did it change?'**
  String get accountPasswordRefused;

  /// No description provided for @accountEditServers.
  ///
  /// In en, this message translates to:
  /// **'Edit servers'**
  String get accountEditServers;

  /// No description provided for @accountSignInAlert.
  ///
  /// In en, this message translates to:
  /// **'Tell me when it can\'t sign in'**
  String get accountSignInAlert;

  /// No description provided for @accountSignInAlertNote.
  ///
  /// In en, this message translates to:
  /// **'One notice, the first time the password is refused'**
  String get accountSignInAlertNote;

  /// No description provided for @accountRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get accountRemove;

  /// No description provided for @accountRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from this device?'**
  String accountRemoveTitle(String name);

  /// No description provided for @accountRemoveNote.
  ///
  /// In en, this message translates to:
  /// **'Its mail here is deleted. On the server everything stays as it is.'**
  String get accountRemoveNote;

  /// No description provided for @accountRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get accountRemoveConfirm;

  /// No description provided for @accountServersTitle.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get accountServersTitle;

  /// No description provided for @accountServersSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get accountServersSave;

  /// No description provided for @accountServersChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get accountServersChecking;

  /// No description provided for @accountDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'{name}, {email}'**
  String accountDetailsLabel(String name, String email);

  /// No description provided for @noticeSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} can\'t sign in'**
  String noticeSignInTitle(String name);

  /// No description provided for @orStartFrom.
  ///
  /// In en, this message translates to:
  /// **'Or start from'**
  String get orStartFrom;

  /// No description provided for @needsAppPassword.
  ///
  /// In en, this message translates to:
  /// **'{provider} needs an app password'**
  String needsAppPassword(String provider);

  /// No description provided for @fastmailNeedsToken.
  ///
  /// In en, this message translates to:
  /// **'Fastmail needs an API token'**
  String get fastmailNeedsToken;

  /// No description provided for @gmailStep1.
  ///
  /// In en, this message translates to:
  /// **'Turn on 2-Step Verification in your Google Account.'**
  String get gmailStep1;

  /// No description provided for @gmailStep2.
  ///
  /// In en, this message translates to:
  /// **'Open App passwords and create one named “Piuma”.'**
  String get gmailStep2;

  /// No description provided for @gmailStep3.
  ///
  /// In en, this message translates to:
  /// **'Paste the 16 letters here.'**
  String get gmailStep3;

  /// No description provided for @openAppPasswords.
  ///
  /// In en, this message translates to:
  /// **'Open App passwords'**
  String get openAppPasswords;

  /// No description provided for @icloudStep1.
  ///
  /// In en, this message translates to:
  /// **'Turn on two-factor authentication for your Apple Account.'**
  String get icloudStep1;

  /// No description provided for @icloudStep2.
  ///
  /// In en, this message translates to:
  /// **'In Sign-In and Security, open App-Specific Passwords and create one named “Piuma”.'**
  String get icloudStep2;

  /// No description provided for @icloudStep3.
  ///
  /// In en, this message translates to:
  /// **'Paste it here.'**
  String get icloudStep3;

  /// No description provided for @openAppleAccount.
  ///
  /// In en, this message translates to:
  /// **'Open Apple Account'**
  String get openAppleAccount;

  /// No description provided for @fastmailStep1.
  ///
  /// In en, this message translates to:
  /// **'In Settings, open Privacy & Security, then Manage API tokens.'**
  String get fastmailStep1;

  /// No description provided for @fastmailStep2.
  ///
  /// In en, this message translates to:
  /// **'Create a token named “Piuma” with access to Email and Email submission.'**
  String get fastmailStep2;

  /// No description provided for @fastmailStep3.
  ///
  /// In en, this message translates to:
  /// **'Paste it here.'**
  String get fastmailStep3;

  /// No description provided for @openApiTokens.
  ///
  /// In en, this message translates to:
  /// **'Open API tokens'**
  String get openApiTokens;

  /// No description provided for @appPassword.
  ///
  /// In en, this message translates to:
  /// **'App password'**
  String get appPassword;

  /// No description provided for @apiToken.
  ///
  /// In en, this message translates to:
  /// **'API token'**
  String get apiToken;

  /// No description provided for @pecWhichProvider.
  ///
  /// In en, this message translates to:
  /// **'Who runs your PEC?'**
  String get pecWhichProvider;

  /// No description provided for @pecWhichProviderHint.
  ///
  /// In en, this message translates to:
  /// **'Certified mail comes with the servers of its provider.'**
  String get pecWhichProviderHint;

  /// No description provided for @signInToPec.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {provider}'**
  String signInToPec(String provider);

  /// No description provided for @pecStep1.
  ///
  /// In en, this message translates to:
  /// **'Use the full PEC address.'**
  String get pecStep1;

  /// No description provided for @pecStep2.
  ///
  /// In en, this message translates to:
  /// **'Use the mailbox password, the one you use for webmail.'**
  String get pecStep2;

  /// No description provided for @verifiedSenderSetting.
  ///
  /// In en, this message translates to:
  /// **'Show verified sender'**
  String get verifiedSenderSetting;

  /// No description provided for @verifiedSenderSettingHint.
  ///
  /// In en, this message translates to:
  /// **'Marks senders your mail server checked with DKIM, SPF and DMARC.'**
  String get verifiedSenderSettingHint;

  /// No description provided for @verifiedBadge.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verifiedBadge;

  /// No description provided for @verifiedSenderLabel.
  ///
  /// In en, this message translates to:
  /// **'Verified sender'**
  String get verifiedSenderLabel;

  /// No description provided for @ruleFieldBody.
  ///
  /// In en, this message translates to:
  /// **'the body'**
  String get ruleFieldBody;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolder;

  /// No description provided for @newFolderName.
  ///
  /// In en, this message translates to:
  /// **'New folder name'**
  String get newFolderName;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @newFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'The server didn\'t make the folder. Try another name.'**
  String get newFolderFailed;

  /// No description provided for @groupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groupsTitle;

  /// No description provided for @groupsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bring together addresses from different accounts and domains. Each group has its own color, its own signature and, if you like, its own Inbox.'**
  String get groupsSubtitle;

  /// No description provided for @groupsNone.
  ///
  /// In en, this message translates to:
  /// **'No groups yet. A group gathers addresses, even from different accounts, under one color and one signature.'**
  String get groupsNone;

  /// No description provided for @groupsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None} other{{count}}}'**
  String groupsCount(int count);

  /// No description provided for @groupAddresses.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 address} other{{count} addresses}}'**
  String groupAddresses(int count);

  /// No description provided for @groupSignatureShort.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get groupSignatureShort;

  /// No description provided for @groupSendFromShort.
  ///
  /// In en, this message translates to:
  /// **'Send from'**
  String get groupSendFromShort;

  /// No description provided for @groupNoSignature.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get groupNoSignature;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @groupColor.
  ///
  /// In en, this message translates to:
  /// **'Group color'**
  String get groupColor;

  /// No description provided for @groupAddressesHeading.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get groupAddressesHeading;

  /// No description provided for @groupAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get groupAccount;

  /// No description provided for @groupAlias.
  ///
  /// In en, this message translates to:
  /// **'Alias'**
  String get groupAlias;

  /// No description provided for @groupAccountNote.
  ///
  /// In en, this message translates to:
  /// **'{name} account'**
  String groupAccountNote(String name);

  /// No description provided for @groupAliasNote.
  ///
  /// In en, this message translates to:
  /// **'on {email}'**
  String groupAliasNote(String email);

  /// No description provided for @groupRemoveAddress.
  ///
  /// In en, this message translates to:
  /// **'Remove {email} from the group'**
  String groupRemoveAddress(String email);

  /// No description provided for @groupAddAddress.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get groupAddAddress;

  /// No description provided for @groupDefaultSignature.
  ///
  /// In en, this message translates to:
  /// **'Default signature'**
  String get groupDefaultSignature;

  /// No description provided for @groupSendFrom.
  ///
  /// In en, this message translates to:
  /// **'Send new emails from'**
  String get groupSendFrom;

  /// No description provided for @groupSeparateInbox.
  ///
  /// In en, this message translates to:
  /// **'Separate Inbox'**
  String get groupSeparateInbox;

  /// No description provided for @groupSeparateOn.
  ///
  /// In en, this message translates to:
  /// **'Gets its own item in the sidebar. Also stays in the Unified inbox.'**
  String get groupSeparateOn;

  /// No description provided for @groupSeparateOff.
  ///
  /// In en, this message translates to:
  /// **'Its emails live only in the Unified inbox.'**
  String get groupSeparateOff;

  /// No description provided for @groupNotifyOn.
  ///
  /// In en, this message translates to:
  /// **'Follows your Notifications rules.'**
  String get groupNotifyOn;

  /// No description provided for @groupNotifyOff.
  ///
  /// In en, this message translates to:
  /// **'No alerts for this group.'**
  String get groupNotifyOff;

  /// No description provided for @groupReplyAsWritten.
  ///
  /// In en, this message translates to:
  /// **'Always reply from the address they wrote to'**
  String get groupReplyAsWritten;

  /// No description provided for @groupReplyOn.
  ///
  /// In en, this message translates to:
  /// **'If someone writes to {email}, your reply goes from {email}, with that group\'s signature.'**
  String groupReplyOn(String email);

  /// No description provided for @groupReplyOnAny.
  ///
  /// In en, this message translates to:
  /// **'If someone writes to one of your aliases, your reply goes from it, with its group\'s signature.'**
  String get groupReplyOnAny;

  /// No description provided for @groupReplyOff.
  ///
  /// In en, this message translates to:
  /// **'Replies go from the group\'s default address.'**
  String get groupReplyOff;

  /// No description provided for @groupNew.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get groupNew;

  /// No description provided for @groupNewName.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get groupNewName;

  /// No description provided for @groupDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get groupDelete;

  /// No description provided for @groupDeleteAsk.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String groupDeleteAsk(String name);

  /// No description provided for @groupDeleteNote.
  ///
  /// In en, this message translates to:
  /// **'Its addresses stay on their accounts; only the group goes.'**
  String get groupDeleteNote;

  /// No description provided for @groupYourAddresses.
  ///
  /// In en, this message translates to:
  /// **'Your addresses'**
  String get groupYourAddresses;

  /// No description provided for @groupMovesHere.
  ///
  /// In en, this message translates to:
  /// **'In another group: moves here'**
  String get groupMovesHere;

  /// No description provided for @groupFoundInSent.
  ///
  /// In en, this message translates to:
  /// **'Found in your sent mail'**
  String get groupFoundInSent;

  /// No description provided for @groupNewAlias.
  ///
  /// In en, this message translates to:
  /// **'New alias'**
  String get groupNewAlias;

  /// No description provided for @groupNewAliasHint.
  ///
  /// In en, this message translates to:
  /// **'name@domain.com'**
  String get groupNewAliasHint;

  /// No description provided for @groupAliasOn.
  ///
  /// In en, this message translates to:
  /// **'on'**
  String get groupAliasOn;

  /// No description provided for @groupAddAlias.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get groupAddAlias;

  /// No description provided for @groupAliasInvalid.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like an email address.'**
  String get groupAliasInvalid;

  /// No description provided for @fromAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get fromAutomatic;

  /// No description provided for @fromAutomaticWhy.
  ///
  /// In en, this message translates to:
  /// **'Chosen because {name} wrote to {email}'**
  String fromAutomaticWhy(String name, String email);

  /// No description provided for @rowWrittenTo.
  ///
  /// In en, this message translates to:
  /// **'to {email}'**
  String rowWrittenTo(String email);

  /// No description provided for @groupsAll.
  ///
  /// In en, this message translates to:
  /// **'All groups'**
  String get groupsAll;

  /// No description provided for @groupExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand {name}'**
  String groupExpand(String name);

  /// No description provided for @groupCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse {name}'**
  String groupCollapse(String name);

  /// No description provided for @groupUnreadLine.
  ///
  /// In en, this message translates to:
  /// **'{addresses, plural, =1{1 address} other{{addresses} addresses}} · {unread} unread'**
  String groupUnreadLine(int addresses, int unread);

  /// No description provided for @groupsAllLine.
  ///
  /// In en, this message translates to:
  /// **'{groups, plural, =1{1 group} other{{groups} groups}} · {addresses, plural, =1{1 address} other{{addresses} addresses}} · {unread} unread'**
  String groupsAllLine(int groups, int addresses, int unread);

  /// No description provided for @groupOnly.
  ///
  /// In en, this message translates to:
  /// **'Only {email}'**
  String groupOnly(String email);

  /// No description provided for @groupOnlyClear.
  ///
  /// In en, this message translates to:
  /// **'Only {email}. Show the whole group'**
  String groupOnlyClear(String email);

  /// No description provided for @groupSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get groupSheetTitle;

  /// No description provided for @groupSheetLine.
  ///
  /// In en, this message translates to:
  /// **'{addresses, plural, =1{1 address} other{{addresses} addresses}} · {groups, plural, =1{1 group} other{{groups} groups}}'**
  String groupSheetLine(int addresses, int groups);

  /// No description provided for @groupSheetLabel.
  ///
  /// In en, this message translates to:
  /// **'Choose group'**
  String get groupSheetLabel;

  /// No description provided for @groupManage.
  ///
  /// In en, this message translates to:
  /// **'Manage groups'**
  String get groupManage;

  /// No description provided for @groupTitleAll.
  ///
  /// In en, this message translates to:
  /// **'Group: all. Change group'**
  String get groupTitleAll;

  /// No description provided for @groupTitleOne.
  ///
  /// In en, this message translates to:
  /// **'Group: {name}. Change group'**
  String groupTitleOne(String name);

  /// No description provided for @syncTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices & sync'**
  String get syncTitle;

  /// No description provided for @syncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your settings on every device, end-to-end encrypted'**
  String get syncSubtitle;

  /// No description provided for @syncOff.
  ///
  /// In en, this message translates to:
  /// **'Off · this device only'**
  String get syncOff;

  /// No description provided for @syncOffBody.
  ///
  /// In en, this message translates to:
  /// **'Keep your accounts, groups, signatures and settings on every device. They are encrypted here and stored in a hidden folder of one of your mailboxes. No server.'**
  String get syncOffBody;

  /// No description provided for @syncOffNote.
  ///
  /// In en, this message translates to:
  /// **'Passwords travel only inside the encrypted copy.'**
  String get syncOffNote;

  /// No description provided for @syncStoreIn.
  ///
  /// In en, this message translates to:
  /// **'Store it in'**
  String get syncStoreIn;

  /// No description provided for @syncMailbox.
  ///
  /// In en, this message translates to:
  /// **'Sync mailbox'**
  String get syncMailbox;

  /// No description provided for @syncMoving.
  ///
  /// In en, this message translates to:
  /// **'Moving…'**
  String get syncMoving;

  /// No description provided for @syncFailTaken.
  ///
  /// In en, this message translates to:
  /// **'That mailbox already holds another sync space.'**
  String get syncFailTaken;

  /// No description provided for @syncTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on sync'**
  String get syncTurnOn;

  /// No description provided for @syncAllSynced.
  ///
  /// In en, this message translates to:
  /// **'All synced'**
  String get syncAllSynced;

  /// No description provided for @syncNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get syncNotYet;

  /// No description provided for @syncOnBody.
  ///
  /// In en, this message translates to:
  /// **'Accounts, groups, signatures and settings are encrypted and stored in your {name} mailbox. No server.'**
  String syncOnBody(String name);

  /// No description provided for @syncOnLine.
  ///
  /// In en, this message translates to:
  /// **'{email} · hidden folder · end-to-end encrypted'**
  String syncOnLine(String email);

  /// No description provided for @syncDevices.
  ///
  /// In en, this message translates to:
  /// **'Linked devices'**
  String get syncDevices;

  /// No description provided for @syncThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get syncThisDevice;

  /// No description provided for @syncActiveNow.
  ///
  /// In en, this message translates to:
  /// **'Active now'**
  String get syncActiveNow;

  /// No description provided for @syncActive.
  ///
  /// In en, this message translates to:
  /// **'Active {ago}'**
  String syncActive(String ago);

  /// No description provided for @syncHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String syncHoursAgo(int count);

  /// No description provided for @syncYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get syncYesterday;

  /// No description provided for @syncDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String syncDaysAgo(int count);

  /// No description provided for @syncUnlink.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get syncUnlink;

  /// No description provided for @syncUnlinkName.
  ///
  /// In en, this message translates to:
  /// **'Unlink {name}'**
  String syncUnlinkName(String name);

  /// No description provided for @syncUnlinkAsk.
  ///
  /// In en, this message translates to:
  /// **'Unlink {name}?'**
  String syncUnlinkAsk(String name);

  /// No description provided for @syncUnlinkNote.
  ///
  /// In en, this message translates to:
  /// **'It keeps what it has now but won\'t get changes any more. Your recovery phrase changes too: you\'ll write down the new one.'**
  String get syncUnlinkNote;

  /// No description provided for @syncLinkNew.
  ///
  /// In en, this message translates to:
  /// **'Link a new device'**
  String get syncLinkNew;

  /// No description provided for @syncLinkBody.
  ///
  /// In en, this message translates to:
  /// **'On the new device, open Piuma, choose “I already use Piuma on another device” and sign in to {email}. It shows 6 digits, and this device asks for them.'**
  String syncLinkBody(String email);

  /// No description provided for @syncLinkWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the new device…'**
  String get syncLinkWaiting;

  /// No description provided for @syncLinkScan.
  ///
  /// In en, this message translates to:
  /// **'On the new phone, open Piuma, choose “I already use Piuma on another device” and scan this code.'**
  String get syncLinkScan;

  /// No description provided for @syncLinkQrLabel.
  ///
  /// In en, this message translates to:
  /// **'QR code to link a new device'**
  String get syncLinkQrLabel;

  /// No description provided for @syncLinkNewCode.
  ///
  /// In en, this message translates to:
  /// **'{waiting} · new code in {time}'**
  String syncLinkNewCode(String waiting, String time);

  /// No description provided for @syncLinkNoCamera.
  ///
  /// In en, this message translates to:
  /// **'No camera? Sign in to {email} on the new device: it shows 6 digits, and this device asks for them.'**
  String syncLinkNoCamera(String email);

  /// No description provided for @syncLinked.
  ///
  /// In en, this message translates to:
  /// **'{name} linked'**
  String syncLinked(String name);

  /// No description provided for @syncPhraseRow.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase'**
  String get syncPhraseRow;

  /// No description provided for @syncPhraseRowLine.
  ///
  /// In en, this message translates to:
  /// **'Opens your space if every device is lost'**
  String get syncPhraseRowLine;

  /// No description provided for @syncShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get syncShow;

  /// No description provided for @syncPhraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Your recovery phrase'**
  String get syncPhraseTitle;

  /// No description provided for @syncPhraseBody.
  ///
  /// In en, this message translates to:
  /// **'If you lose every device, these 24 words are the only way back into your space. Write them on paper and keep them safe. Piuma can\'t recover them for you.'**
  String get syncPhraseBody;

  /// No description provided for @syncPhraseNewTitle.
  ///
  /// In en, this message translates to:
  /// **'Your new recovery phrase'**
  String get syncPhraseNewTitle;

  /// No description provided for @syncPhraseNewBody.
  ///
  /// In en, this message translates to:
  /// **'{name} can\'t open your space any more, and the old phrase no longer works. Write these 24 words on paper instead.'**
  String syncPhraseNewBody(String name);

  /// No description provided for @syncPhraseWarn.
  ///
  /// In en, this message translates to:
  /// **'Anyone with these words can read your space.'**
  String get syncPhraseWarn;

  /// No description provided for @syncPhraseDone.
  ///
  /// In en, this message translates to:
  /// **'I wrote them down'**
  String get syncPhraseDone;

  /// No description provided for @syncPhraseWord.
  ///
  /// In en, this message translates to:
  /// **'{index}. {word}'**
  String syncPhraseWord(int index, String word);

  /// No description provided for @syncAskTitle.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, phone{New phone wants to connect} tablet{New tablet wants to connect} other{New computer wants to connect}}'**
  String syncAskTitle(String kind);

  /// No description provided for @syncAskLine.
  ///
  /// In en, this message translates to:
  /// **'{name} · asked {ago}'**
  String syncAskLine(String name, String ago);

  /// No description provided for @syncAskCode.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, phone{Enter the 6 digits the phone shows.} tablet{Enter the 6 digits the tablet shows.} other{Enter the 6 digits the computer shows.}}'**
  String syncAskCode(String kind);

  /// No description provided for @syncAskDigits.
  ///
  /// In en, this message translates to:
  /// **'The 6 digits'**
  String get syncAskDigits;

  /// No description provided for @syncNotMe.
  ///
  /// In en, this message translates to:
  /// **'Not me'**
  String get syncNotMe;

  /// No description provided for @syncApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get syncApprove;

  /// No description provided for @syncApproving.
  ///
  /// In en, this message translates to:
  /// **'Approving…'**
  String get syncApproving;

  /// No description provided for @syncFailOffline.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach {email}. Try again when you\'re online.'**
  String syncFailOffline(String email);

  /// No description provided for @syncFailExpired.
  ///
  /// In en, this message translates to:
  /// **'The request expired. Ask again from the new device.'**
  String get syncFailExpired;

  /// No description provided for @syncFailOther.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get syncFailOther;

  /// No description provided for @syncRowOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get syncRowOn;

  /// No description provided for @syncRowOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get syncRowOff;

  /// No description provided for @pairAlready.
  ///
  /// In en, this message translates to:
  /// **'I already use Piuma on another device'**
  String get pairAlready;

  /// No description provided for @pairAlreadyOn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to one of your mailboxes. If it holds your space, you\'ll link this device next.'**
  String get pairAlreadyOn;

  /// No description provided for @pairLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Link this phone'**
  String get pairLinkTitle;

  /// No description provided for @pairLinkBody.
  ///
  /// In en, this message translates to:
  /// **'On your computer, open Settings › Devices & sync › Link a new device, then scan the code it shows.'**
  String get pairLinkBody;

  /// No description provided for @pairScan.
  ///
  /// In en, this message translates to:
  /// **'Scan code'**
  String get pairScan;

  /// No description provided for @pairSignInInstead.
  ///
  /// In en, this message translates to:
  /// **'Sign in instead'**
  String get pairSignInInstead;

  /// No description provided for @pairScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point at the code on your computer'**
  String get pairScanHint;

  /// No description provided for @pairScanWhere.
  ///
  /// In en, this message translates to:
  /// **'Settings › Devices & sync › Link a new device'**
  String get pairScanWhere;

  /// No description provided for @pairNoCamera.
  ///
  /// In en, this message translates to:
  /// **'Piuma can\'t use the camera. Allow it in the system settings, or sign in instead.'**
  String get pairNoCamera;

  /// No description provided for @pairLastStep.
  ///
  /// In en, this message translates to:
  /// **'One last step'**
  String get pairLastStep;

  /// No description provided for @pairLastStepBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to the mailbox that holds your space. The other accounts come over on their own.'**
  String get pairLastStepBody;

  /// No description provided for @pairConfirmsOwn.
  ///
  /// In en, this message translates to:
  /// **'Your computer confirms on its own: it showed you the code.'**
  String get pairConfirmsOwn;

  /// No description provided for @pairLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get pairLink;

  /// No description provided for @pairLinking.
  ///
  /// In en, this message translates to:
  /// **'Linking…'**
  String get pairLinking;

  /// No description provided for @pairFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'We found your space'**
  String get pairFoundTitle;

  /// No description provided for @pairFoundBody.
  ///
  /// In en, this message translates to:
  /// **'The {email} mailbox holds an encrypted copy of your settings. Only your devices can read it.'**
  String pairFoundBody(String email);

  /// No description provided for @pairAccounts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{account} other{accounts}}'**
  String pairAccounts(int count);

  /// No description provided for @pairGroups.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{group} other{groups}}'**
  String pairGroups(int count);

  /// No description provided for @pairSignatures.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{signature} other{signatures}}'**
  String pairSignatures(int count);

  /// No description provided for @pairEncrypted.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted · updated {when}'**
  String pairEncrypted(String when);

  /// No description provided for @pairConfirmFrom.
  ///
  /// In en, this message translates to:
  /// **'For security, confirm from a device that\'s already paired: {name}, active {ago}.'**
  String pairConfirmFrom(String name, String ago);

  /// No description provided for @pairShowCode.
  ///
  /// In en, this message translates to:
  /// **'Show code'**
  String get pairShowCode;

  /// No description provided for @pairUsePhrase.
  ///
  /// In en, this message translates to:
  /// **'Use recovery phrase'**
  String get pairUsePhrase;

  /// No description provided for @pairCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, phone{Confirm on your phone} tablet{Confirm on your tablet} other{Confirm on your computer}}'**
  String pairCodeTitle(String kind);

  /// No description provided for @pairCodeBody.
  ///
  /// In en, this message translates to:
  /// **'Open Piuma on {name} and enter the code.'**
  String pairCodeBody(String name);

  /// No description provided for @pairCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code {digits}'**
  String pairCodeLabel(String digits);

  /// No description provided for @pairExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {time}'**
  String pairExpiresIn(String time);

  /// No description provided for @pairWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name} to confirm…'**
  String pairWaiting(String name);

  /// No description provided for @pairStep1.
  ///
  /// In en, this message translates to:
  /// **'{name} will show “{title}”'**
  String pairStep1(String name, String title);

  /// No description provided for @pairStep2.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6 digits and tap Approve'**
  String get pairStep2;

  /// No description provided for @pairExpired.
  ///
  /// In en, this message translates to:
  /// **'The code expired.'**
  String get pairExpired;

  /// No description provided for @pairRefused.
  ///
  /// In en, this message translates to:
  /// **'{name} said this wasn\'t you.'**
  String pairRefused(String name);

  /// No description provided for @pairWrongCode.
  ///
  /// In en, this message translates to:
  /// **'The code typed there wasn\'t this one.'**
  String get pairWrongCode;

  /// No description provided for @pairNewCode.
  ///
  /// In en, this message translates to:
  /// **'Show a new code'**
  String get pairNewCode;

  /// No description provided for @pairPhraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase'**
  String get pairPhraseTitle;

  /// No description provided for @pairPhraseBody.
  ///
  /// In en, this message translates to:
  /// **'Type the 24 words you wrote down, in order, with spaces between them.'**
  String get pairPhraseBody;

  /// No description provided for @pairPhraseCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of 24 words'**
  String pairPhraseCount(int count);

  /// No description provided for @pairPhraseWrong.
  ///
  /// In en, this message translates to:
  /// **'These words don\'t open your space. Check them and try again.'**
  String get pairPhraseWrong;

  /// No description provided for @pairContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get pairContinue;

  /// No description provided for @pairDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, phone{Phone paired} tablet{Tablet paired} other{Computer paired}}'**
  String pairDoneTitle(String kind);

  /// No description provided for @pairDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Here\'s what came over from your encrypted space.'**
  String get pairDoneBody;

  /// No description provided for @pairDoneAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get pairDoneAccounts;

  /// No description provided for @pairDoneGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get pairDoneGroups;

  /// No description provided for @pairDoneSettings.
  ///
  /// In en, this message translates to:
  /// **'Signatures and settings synced'**
  String get pairDoneSettings;

  /// No description provided for @pairSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get pairSynced;

  /// No description provided for @pairStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of 3'**
  String pairStepOf(int step);

  /// No description provided for @pairTodayAt.
  ///
  /// In en, this message translates to:
  /// **'today at {time}'**
  String pairTodayAt(String time);

  /// No description provided for @pairYesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'yesterday at {time}'**
  String pairYesterdayAt(String time);

  /// No description provided for @pairOnDay.
  ///
  /// In en, this message translates to:
  /// **'on {day}'**
  String pairOnDay(String day);

  /// No description provided for @keyOpenWindow.
  ///
  /// In en, this message translates to:
  /// **'open in new window'**
  String get keyOpenWindow;

  /// No description provided for @syncedOnDevices.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Synced on 1 device} other{Synced on {count} devices}}'**
  String syncedOnDevices(int count);

  /// No description provided for @ruleNewsletters.
  ///
  /// In en, this message translates to:
  /// **'When a newsletter was read more than 7 days ago'**
  String get ruleNewsletters;

  /// No description provided for @ruleBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built in · every account'**
  String get ruleBuiltIn;

  /// No description provided for @syncTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off sync on this device'**
  String get syncTurnOff;

  /// No description provided for @syncTurnOffAsk.
  ///
  /// In en, this message translates to:
  /// **'Turn off sync on this device?'**
  String get syncTurnOffAsk;

  /// No description provided for @syncTurnOffOne.
  ///
  /// In en, this message translates to:
  /// **'This device leaves your space and stops getting changes. Its accounts and mail stay here. {name} keeps syncing.'**
  String syncTurnOffOne(String name);

  /// No description provided for @syncTurnOffMany.
  ///
  /// In en, this message translates to:
  /// **'This device leaves your space and stops getting changes. Its accounts and mail stay here. {names} keep syncing.'**
  String syncTurnOffMany(String names);

  /// No description provided for @syncTurnOffLast.
  ///
  /// In en, this message translates to:
  /// **'This device leaves your space and stops getting changes. Its accounts and mail stay here. This is your only device: the encrypted copy in {email} is deleted too.'**
  String syncTurnOffLast(String email);

  /// No description provided for @syncTurnOffButton.
  ///
  /// In en, this message translates to:
  /// **'Turn off sync'**
  String get syncTurnOffButton;

  /// No description provided for @listAnd.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get listAnd;

  /// No description provided for @composeDropFiles.
  ///
  /// In en, this message translates to:
  /// **'Drop to attach'**
  String get composeDropFiles;

  /// No description provided for @serverType.
  ///
  /// In en, this message translates to:
  /// **'Server type'**
  String get serverType;

  /// No description provided for @imapAndSmtp.
  ///
  /// In en, this message translates to:
  /// **'IMAP and SMTP'**
  String get imapAndSmtp;

  /// No description provided for @jmapServer.
  ///
  /// In en, this message translates to:
  /// **'JMAP server'**
  String get jmapServer;

  /// No description provided for @jmapServerHint.
  ///
  /// In en, this message translates to:
  /// **'The server\'s name, or the full address of its JMAP session.'**
  String get jmapServerHint;

  /// No description provided for @jmapSignsIn.
  ///
  /// In en, this message translates to:
  /// **'One server reads, sends and brings new mail at once. You sign in with your address.'**
  String get jmapSignsIn;

  /// No description provided for @shortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get shortcutsTitle;

  /// No description provided for @shortcutsLine.
  ///
  /// In en, this message translates to:
  /// **'Just the essentials. Everything else is in {keys}.'**
  String shortcutsLine(String keys);

  /// No description provided for @shortcutsTable.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get shortcutsTable;

  /// No description provided for @shortcutPalette.
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get shortcutPalette;

  /// No description provided for @ruleSuggest.
  ///
  /// In en, this message translates to:
  /// **'You often move emails from {name} to {folder}. Create a rule?'**
  String ruleSuggest(String name, String folder);

  /// No description provided for @ruleSuggestMeta.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Suggested on-device · 1 move in the last month} other{Suggested on-device · {count} moves in the last month}}'**
  String ruleSuggestMeta(int count);

  /// No description provided for @actionForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get actionForward;

  /// No description provided for @forwardBlock.
  ///
  /// In en, this message translates to:
  /// **'---------- Forwarded message ----------\nFrom: {from}\nDate: {date}\nTo: {to}\nSubject: {subject}'**
  String forwardBlock(String from, String date, String to, String subject);

  /// No description provided for @forwardDate.
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}'**
  String forwardDate(String date, String time);

  /// No description provided for @folderWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get folderWaiting;

  /// No description provided for @waitingSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} sent · no reply yet'**
  String waitingSummary(int count);

  /// No description provided for @waitingNoReply.
  ///
  /// In en, this message translates to:
  /// **'No reply yet'**
  String get waitingNoReply;

  /// No description provided for @waitingTo.
  ///
  /// In en, this message translates to:
  /// **'To '**
  String get waitingTo;

  /// No description provided for @waitingDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String waitingDays(int count);

  /// No description provided for @waitingToday.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get waitingToday;

  /// No description provided for @waitingYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get waitingYesterday;

  /// No description provided for @waitingLine.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sent email waiting for a reply} other{{count} sent emails waiting for a reply}}'**
  String waitingLine(int count);

  /// No description provided for @writeAgain.
  ///
  /// In en, this message translates to:
  /// **'Write again'**
  String get writeAgain;

  /// No description provided for @stopWaiting.
  ///
  /// In en, this message translates to:
  /// **'Stop waiting'**
  String get stopWaiting;

  /// No description provided for @stoppedWaiting.
  ///
  /// In en, this message translates to:
  /// **'Out of Waiting. It stays in Sent.'**
  String get stoppedWaiting;

  /// No description provided for @remindMe.
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get remindMe;

  /// No description provided for @remindTitle.
  ///
  /// In en, this message translates to:
  /// **'Remind me if nobody replies'**
  String get remindTitle;

  /// No description provided for @remindTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get remindTomorrow;

  /// No description provided for @remindInDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{In 1 day} other{In {count} days}}'**
  String remindInDays(int count);

  /// No description provided for @remindNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get remindNextWeek;

  /// No description provided for @remindPickDate.
  ///
  /// In en, this message translates to:
  /// **'Pick a date…'**
  String get remindPickDate;

  /// No description provided for @remindNever.
  ///
  /// In en, this message translates to:
  /// **'Don’t remind me'**
  String get remindNever;

  /// No description provided for @remindChipToday.
  ///
  /// In en, this message translates to:
  /// **'Remind me at {time}'**
  String remindChipToday(String time);

  /// No description provided for @remindChipTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Remind me tomorrow'**
  String get remindChipTomorrow;

  /// No description provided for @remindChipInDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Remind me in 1 day} other{Remind me in {count} days}}'**
  String remindChipInDays(int count);

  /// No description provided for @remindChipOn.
  ///
  /// In en, this message translates to:
  /// **'Remind me on {date}'**
  String remindChipOn(String date);

  /// No description provided for @remindAt.
  ///
  /// In en, this message translates to:
  /// **'Remind me {when}'**
  String remindAt(String when);

  /// No description provided for @remindNoReply.
  ///
  /// In en, this message translates to:
  /// **'No reply from {name}'**
  String remindNoReply(String name);

  /// No description provided for @remindSentToday.
  ///
  /// In en, this message translates to:
  /// **'sent today'**
  String get remindSentToday;

  /// No description provided for @remindSentYesterday.
  ///
  /// In en, this message translates to:
  /// **'sent yesterday'**
  String get remindSentYesterday;

  /// No description provided for @remindSentDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{sent 1 day ago} other{sent {count} days ago}}'**
  String remindSentDaysAgo(int count);

  /// No description provided for @senderSharedFiles.
  ///
  /// In en, this message translates to:
  /// **'Shared attachments'**
  String get senderSharedFiles;

  /// No description provided for @senderFileCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attachment} other{{count} attachments}}'**
  String senderFileCount(int count);

  /// No description provided for @senderNoFiles.
  ///
  /// In en, this message translates to:
  /// **'No attachments from them yet.'**
  String get senderNoFiles;

  /// No description provided for @senderAddresses.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get senderAddresses;

  /// No description provided for @senderAddressNote.
  ///
  /// In en, this message translates to:
  /// **'{account} · {count, plural, =1{1 email} other{{count} emails}}'**
  String senderAddressNote(String account, int count);

  /// No description provided for @senderCopyAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get senderCopyAddress;

  /// No description provided for @senderRules.
  ///
  /// In en, this message translates to:
  /// **'Rules & folders'**
  String get senderRules;

  /// No description provided for @senderContent.
  ///
  /// In en, this message translates to:
  /// **'Sender content'**
  String get senderContent;

  /// No description provided for @folderReorder.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder {name}'**
  String folderReorder(String name);

  /// No description provided for @folderMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get folderMoveUp;

  /// No description provided for @folderMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get folderMoveDown;

  /// No description provided for @ruleUnopenedNewsletters.
  ///
  /// In en, this message translates to:
  /// **'Newsletters'**
  String get ruleUnopenedNewsletters;

  /// No description provided for @ruleUnopenedFor.
  ///
  /// In en, this message translates to:
  /// **' unopened for '**
  String get ruleUnopenedFor;

  /// No description provided for @ruleUnopenedDays.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get ruleUnopenedDays;

  /// No description provided for @ruleNightly.
  ///
  /// In en, this message translates to:
  /// **'Nightly · {count, plural, =0{every account} =1{1 email archived} other{{count} emails archived}}'**
  String ruleNightly(int count);

  /// No description provided for @rulesWhereSynced.
  ///
  /// In en, this message translates to:
  /// **'Rules run on this device and sync across all your devices'**
  String get rulesWhereSynced;

  /// No description provided for @rulesWhereSyncedAt.
  ///
  /// In en, this message translates to:
  /// **'Rules run on this device and sync across all your devices · updated {ago}'**
  String rulesWhereSyncedAt(String ago);

  /// No description provided for @calSynced.
  ///
  /// In en, this message translates to:
  /// **'Connections sync across all your devices; passwords travel encrypted and stay in the system keychain.'**
  String get calSynced;

  /// No description provided for @calUpdatesHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{updates every hour} other{updates every {count} hours}}'**
  String calUpdatesHours(int count);

  /// No description provided for @calUpdatesDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{updates daily} other{updates every {count} days}}'**
  String calUpdatesDays(int count);

  /// No description provided for @calUpdatesWeekly.
  ///
  /// In en, this message translates to:
  /// **'updates weekly'**
  String get calUpdatesWeekly;

  /// No description provided for @showOriginalLayout.
  ///
  /// In en, this message translates to:
  /// **'Show original layout'**
  String get showOriginalLayout;

  /// No description provided for @originalLayout.
  ///
  /// In en, this message translates to:
  /// **'Original layout'**
  String get originalLayout;

  /// No description provided for @originalLayoutBar.
  ///
  /// In en, this message translates to:
  /// **'Original layout · images and links follow your privacy settings'**
  String get originalLayoutBar;

  /// No description provided for @backToReadingView.
  ///
  /// In en, this message translates to:
  /// **'Back to reading view'**
  String get backToReadingView;

  /// No description provided for @readingView.
  ///
  /// In en, this message translates to:
  /// **'Reading view'**
  String get readingView;

  /// No description provided for @replyFromLabel.
  ///
  /// In en, this message translates to:
  /// **'Reply from'**
  String get replyFromLabel;

  /// No description provided for @senderReadsNoReplies.
  ///
  /// In en, this message translates to:
  /// **'This sender doesn’t read replies'**
  String get senderReadsNoReplies;

  /// No description provided for @replyFromSignature.
  ///
  /// In en, this message translates to:
  /// **'signature {name}'**
  String replyFromSignature(String name);

  /// No description provided for @noticeReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Write a reply…'**
  String get noticeReplyHint;

  /// No description provided for @labelsHeading.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get labelsHeading;

  /// No description provided for @labelsSection.
  ///
  /// In en, this message translates to:
  /// **'LABELS'**
  String get labelsSection;

  /// No description provided for @labelAction.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get labelAction;

  /// No description provided for @labelAdd.
  ///
  /// In en, this message translates to:
  /// **'+ Label'**
  String get labelAdd;

  /// No description provided for @labelNew.
  ///
  /// In en, this message translates to:
  /// **'New label'**
  String get labelNew;

  /// No description provided for @labelFind.
  ///
  /// In en, this message translates to:
  /// **'Find or create a label'**
  String get labelFind;

  /// No description provided for @labelCreate.
  ///
  /// In en, this message translates to:
  /// **'Create “{name}”'**
  String labelCreate(String name);

  /// No description provided for @labelRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove the label {name}'**
  String labelRemove(String name);

  /// No description provided for @labelEmails.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 email} other{{count} emails}}'**
  String labelEmails(int count);

  /// No description provided for @labelAccounts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 account} other{{count} accounts}}'**
  String labelAccounts(int count);

  /// No description provided for @labelsLocalNote.
  ///
  /// In en, this message translates to:
  /// **'{account} keeps no labels on the server, so its labels stay on this device.'**
  String labelsLocalNote(String account);

  /// No description provided for @hintLabel.
  ///
  /// In en, this message translates to:
  /// **'label'**
  String get hintLabel;

  /// No description provided for @labelName.
  ///
  /// In en, this message translates to:
  /// **'Label name'**
  String get labelName;

  /// No description provided for @labelEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit label'**
  String get labelEdit;

  /// No description provided for @labelSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get labelSave;

  /// No description provided for @labelCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get labelCreateButton;

  /// No description provided for @labelDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete label'**
  String get labelDelete;

  /// No description provided for @labelDeleteNote.
  ///
  /// In en, this message translates to:
  /// **'It comes off every email; the emails stay where they are.'**
  String get labelDeleteNote;

  /// No description provided for @labelColorAmber.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get labelColorAmber;

  /// No description provided for @labelColorTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get labelColorTeal;

  /// No description provided for @labelColorCoral.
  ///
  /// In en, this message translates to:
  /// **'Coral'**
  String get labelColorCoral;

  /// No description provided for @labelColorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get labelColorBlue;

  /// No description provided for @labelColorViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get labelColorViolet;

  /// No description provided for @labelMenu.
  ///
  /// In en, this message translates to:
  /// **'Label…'**
  String get labelMenu;

  /// No description provided for @ruleDoLabel.
  ///
  /// In en, this message translates to:
  /// **'label'**
  String get ruleDoLabel;

  /// No description provided for @ruleTrayLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get ruleTrayLabel;

  /// No description provided for @rulePickLabel.
  ///
  /// In en, this message translates to:
  /// **'a label'**
  String get rulePickLabel;

  /// No description provided for @ruleNoLabels.
  ///
  /// In en, this message translates to:
  /// **'No labels yet: make one with + Label under Folders & labels.'**
  String get ruleNoLabels;

  /// No description provided for @foldersAndLabelsHeading.
  ///
  /// In en, this message translates to:
  /// **'Folders & labels'**
  String get foldersAndLabelsHeading;

  /// No description provided for @labelsCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get labelsCardTitle;

  /// No description provided for @labelsCardDetail.
  ///
  /// In en, this message translates to:
  /// **'shared across all accounts'**
  String get labelsCardDetail;

  /// No description provided for @labelsNone.
  ///
  /// In en, this message translates to:
  /// **'No labels yet.'**
  String get labelsNone;

  /// No description provided for @rulesFoldersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 folder} other{{count} folders}}'**
  String rulesFoldersCount(int count);

  /// No description provided for @rulesLabelsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 label} other{{count} labels}}'**
  String rulesLabelsCount(int count);

  /// No description provided for @senderPicturesSetting.
  ///
  /// In en, this message translates to:
  /// **'Sender pictures'**
  String get senderPicturesSetting;

  /// No description provided for @senderPicturesSettingHint.
  ///
  /// In en, this message translates to:
  /// **'Photos from your contacts and verified company logos in place of the letters.'**
  String get senderPicturesSettingHint;

  /// No description provided for @websiteIconsSetting.
  ///
  /// In en, this message translates to:
  /// **'Website icons'**
  String get websiteIconsSetting;

  /// No description provided for @websiteIconsSettingHint.
  ///
  /// In en, this message translates to:
  /// **'For companies without a logo. Each website sees your IP address once.'**
  String get websiteIconsSettingHint;

  /// No description provided for @tabletInboxUnread.
  ///
  /// In en, this message translates to:
  /// **'Inbox, {count} unread'**
  String tabletInboxUnread(int count);

  /// No description provided for @tabletAccount.
  ///
  /// In en, this message translates to:
  /// **'{name} account, {email}'**
  String tabletAccount(String name, String email);

  /// No description provided for @tabletSearch.
  ///
  /// In en, this message translates to:
  /// **'Search mail'**
  String get tabletSearch;

  /// No description provided for @tabletSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search or run a command'**
  String get tabletSearchHint;

  /// No description provided for @vaultTrackParcel.
  ///
  /// In en, this message translates to:
  /// **'Track parcel'**
  String get vaultTrackParcel;

  /// No description provided for @vaultTrackingCopied.
  ///
  /// In en, this message translates to:
  /// **'Tracking number copied'**
  String get vaultTrackingCopied;

  /// No description provided for @vaultNeedsYou.
  ///
  /// In en, this message translates to:
  /// **'Needs you'**
  String get vaultNeedsYou;

  /// No description provided for @vaultNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get vaultNext;

  /// No description provided for @vaultOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get vaultOnTheWay;

  /// No description provided for @vaultEverything.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get vaultEverything;

  /// No description provided for @vaultNeedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 thing needs you} other{{count} things need you}}'**
  String vaultNeedCount(int count);

  /// No description provided for @vaultTodayKind.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, flight{a flight today} train{a train today} ferry{a ferry today} bus{a bus today} stay{a check-in today} parking{parking today} car{a hired car today} event{an event today} table{a table today} other{a booking today}}'**
  String vaultTodayKind(String kind);

  /// No description provided for @vaultLegKind.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, flight{Flight} train{Train} ferry{Ferry} bus{Bus} stay{Check-in} parking{Parking} car{Car hire} event{Event} table{Table} other{Booking}}'**
  String vaultLegKind(String kind);

  /// No description provided for @vaultCatParcels.
  ///
  /// In en, this message translates to:
  /// **'Parcels'**
  String get vaultCatParcels;

  /// No description provided for @vaultCatSpending.
  ///
  /// In en, this message translates to:
  /// **'Spending'**
  String get vaultCatSpending;

  /// No description provided for @vaultCatTrips.
  ///
  /// In en, this message translates to:
  /// **'Trips'**
  String get vaultCatTrips;

  /// No description provided for @vaultCatSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get vaultCatSales;

  /// No description provided for @vaultCatSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get vaultCatSubscriptions;

  /// No description provided for @vaultCatReturns.
  ///
  /// In en, this message translates to:
  /// **'Returns & warranty'**
  String get vaultCatReturns;

  /// No description provided for @vaultCatDeadlines.
  ///
  /// In en, this message translates to:
  /// **'Deadlines'**
  String get vaultCatDeadlines;

  /// No description provided for @vaultCatBookings.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get vaultCatBookings;

  /// No description provided for @vaultCatVouchers.
  ///
  /// In en, this message translates to:
  /// **'Gift cards & codes'**
  String get vaultCatVouchers;

  /// No description provided for @vaultCatDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get vaultCatDocuments;

  /// No description provided for @vaultCatCertified.
  ///
  /// In en, this message translates to:
  /// **'Certified mail'**
  String get vaultCatCertified;

  /// No description provided for @vaultOnWayCount.
  ///
  /// In en, this message translates to:
  /// **'{count} on the way'**
  String vaultOnWayCount(int count);

  /// No description provided for @vaultToPickUp.
  ///
  /// In en, this message translates to:
  /// **'{count} to pick up'**
  String vaultToPickUp(int count);

  /// No description provided for @vaultDeliveredCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 delivered} other{{count} delivered}}'**
  String vaultDeliveredCount(int count);

  /// No description provided for @vaultMonthMoney.
  ///
  /// In en, this message translates to:
  /// **'{month} · {money}'**
  String vaultMonthMoney(String month, String money);

  /// No description provided for @vaultOnTripNow.
  ///
  /// In en, this message translates to:
  /// **'On a trip now'**
  String get vaultOnTripNow;

  /// No description provided for @vaultNextWhen.
  ///
  /// In en, this message translates to:
  /// **'Next: {when}'**
  String vaultNextWhen(String when);

  /// No description provided for @vaultPastCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 past trip} other{{count} past trips}}'**
  String vaultPastCount(int count);

  /// No description provided for @vaultToShipCount.
  ///
  /// In en, this message translates to:
  /// **'{count} to ship'**
  String vaultToShipCount(int count);

  /// No description provided for @vaultSoldCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sold'**
  String vaultSoldCount(int count);

  /// No description provided for @vaultPlansLine.
  ///
  /// In en, this message translates to:
  /// **'{count} · {money} a month'**
  String vaultPlansLine(int count, String money);

  /// No description provided for @vaultPlansCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 plan} other{{count} plans}}'**
  String vaultPlansCount(int count);

  /// No description provided for @vaultReturnUntil.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 return until {day}} other{{count} returns, first until {day}}}'**
  String vaultReturnUntil(int count, String day);

  /// No description provided for @vaultWarrantyCount.
  ///
  /// In en, this message translates to:
  /// **'{count} under warranty'**
  String vaultWarrantyCount(int count);

  /// No description provided for @vaultCodesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 code} other{{count} codes}}'**
  String vaultCodesCount(int count);

  /// No description provided for @vaultCountMoney.
  ///
  /// In en, this message translates to:
  /// **'{count} · {money}'**
  String vaultCountMoney(int count, String money);

  /// No description provided for @vaultCertDelivered.
  ///
  /// In en, this message translates to:
  /// **'{count} delivered'**
  String vaultCertDelivered(int count);

  /// No description provided for @vaultTitleWhen.
  ///
  /// In en, this message translates to:
  /// **'{title} · {when}'**
  String vaultTitleWhen(String title, String when);

  /// No description provided for @vaultNeedFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed · {who}'**
  String vaultNeedFailed(String who);

  /// No description provided for @vaultPaymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get vaultPaymentFailed;

  /// No description provided for @vaultWasDue.
  ///
  /// In en, this message translates to:
  /// **'Was due {when}'**
  String vaultWasDue(String when);

  /// No description provided for @vaultShipBy.
  ///
  /// In en, this message translates to:
  /// **'Ship by {when}'**
  String vaultShipBy(String when);

  /// No description provided for @vaultToShip.
  ///
  /// In en, this message translates to:
  /// **'To ship'**
  String get vaultToShip;

  /// No description provided for @vaultYouSend.
  ///
  /// In en, this message translates to:
  /// **'You send'**
  String get vaultYouSend;

  /// No description provided for @vaultSoldOn.
  ///
  /// In en, this message translates to:
  /// **'sold on {where}'**
  String vaultSoldOn(String where);

  /// No description provided for @vaultPickUpBy.
  ///
  /// In en, this message translates to:
  /// **'Pick up by {when}'**
  String vaultPickUpBy(String when);

  /// No description provided for @vaultReadyPickup.
  ///
  /// In en, this message translates to:
  /// **'Ready to pick up'**
  String get vaultReadyPickup;

  /// No description provided for @vaultRenewsWhen.
  ///
  /// In en, this message translates to:
  /// **'Renews {when}'**
  String vaultRenewsWhen(String when);

  /// No description provided for @vaultEndsWhen.
  ///
  /// In en, this message translates to:
  /// **'Ends {when}'**
  String vaultEndsWhen(String when);

  /// No description provided for @vaultPerPeriod.
  ///
  /// In en, this message translates to:
  /// **'{period, select, week{{money} a week} month{{money} a month} year{{money} a year} other{{money}}}'**
  String vaultPerPeriod(String money, String period);

  /// No description provided for @vaultSince.
  ///
  /// In en, this message translates to:
  /// **'since {day}'**
  String vaultSince(String day);

  /// No description provided for @vaultUpdatePayment.
  ///
  /// In en, this message translates to:
  /// **'Update payment'**
  String get vaultUpdatePayment;

  /// No description provided for @vaultCoach.
  ///
  /// In en, this message translates to:
  /// **'Coach'**
  String get vaultCoach;

  /// No description provided for @vaultTicket.
  ///
  /// In en, this message translates to:
  /// **'Ticket'**
  String get vaultTicket;

  /// No description provided for @vaultInHours.
  ///
  /// In en, this message translates to:
  /// **'in {hours} h'**
  String vaultInHours(int hours);

  /// No description provided for @vaultInMinutes.
  ///
  /// In en, this message translates to:
  /// **'in {minutes} min'**
  String vaultInMinutes(int minutes);

  /// No description provided for @vaultDeliveredWeek.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 parcel delivered this week} other{{count} parcels delivered this week}}'**
  String vaultDeliveredWeek(int count);

  /// No description provided for @vaultSpentIn.
  ///
  /// In en, this message translates to:
  /// **'Spent in {month}'**
  String vaultSpentIn(String month);

  /// No description provided for @vaultReceipts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 receipt} other{{count} receipts}}'**
  String vaultReceipts(int count);

  /// No description provided for @vaultExportMonth.
  ///
  /// In en, this message translates to:
  /// **'Export month'**
  String get vaultExportMonth;

  /// No description provided for @vaultSpentTab.
  ///
  /// In en, this message translates to:
  /// **'Spent · {money}'**
  String vaultSpentTab(String money);

  /// No description provided for @vaultMoneyInTab.
  ///
  /// In en, this message translates to:
  /// **'Money in · {money}'**
  String vaultMoneyInTab(String money);

  /// No description provided for @vaultVia.
  ///
  /// In en, this message translates to:
  /// **'via {service}'**
  String vaultVia(String service);

  /// No description provided for @vaultSpendingNote.
  ///
  /// In en, this message translates to:
  /// **'Read on-device from receipts and invoices'**
  String get vaultSpendingNote;

  /// No description provided for @vaultExported.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{{file} saved in Downloads} =1{{file} and 1 PDF saved in Downloads} other{{file} and {count} PDFs saved in Downloads}}'**
  String vaultExported(int count, String file);

  /// No description provided for @vaultNotExported.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t export the month'**
  String get vaultNotExported;

  /// No description provided for @vaultPrevMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get vaultPrevMonth;

  /// No description provided for @vaultNextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get vaultNextMonth;

  /// No description provided for @vaultNothingThisMonth.
  ///
  /// In en, this message translates to:
  /// **'No receipts this month.'**
  String get vaultNothingThisMonth;

  /// No description provided for @vaultSubscriptionsRow.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions · {count}'**
  String vaultSubscriptionsRow(int count);

  /// No description provided for @vaultCsvHeader.
  ///
  /// In en, this message translates to:
  /// **'Date,Who,What,Amount,Currency,Paid via,File,VAT number'**
  String get vaultCsvHeader;

  /// No description provided for @vaultComingUp.
  ///
  /// In en, this message translates to:
  /// **'{count} coming up'**
  String vaultComingUp(int count);

  /// No description provided for @vaultNoTrips.
  ///
  /// In en, this message translates to:
  /// **'No trips ahead'**
  String get vaultNoTrips;

  /// No description provided for @vaultPastTrips.
  ///
  /// In en, this message translates to:
  /// **'Past trips'**
  String get vaultPastTrips;

  /// No description provided for @vaultThisYear.
  ///
  /// In en, this message translates to:
  /// **'{count} this year'**
  String vaultThisYear(int count);

  /// No description provided for @vaultTripNowBack.
  ///
  /// In en, this message translates to:
  /// **'Now · back {when}'**
  String vaultTripNowBack(String when);

  /// No description provided for @vaultLegDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get vaultLegDone;

  /// No description provided for @vaultUntilTime.
  ///
  /// In en, this message translates to:
  /// **'Until {time}'**
  String vaultUntilTime(String time);

  /// No description provided for @vaultUntilDay.
  ///
  /// In en, this message translates to:
  /// **'Until {day}'**
  String vaultUntilDay(String day);

  /// No description provided for @vaultTripsNote.
  ///
  /// In en, this message translates to:
  /// **'Trains, ferries, flights, stays, parking and tickets'**
  String get vaultTripsNote;

  /// No description provided for @vaultNights.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 night} other{{count} nights}}'**
  String vaultNights(int count);

  /// No description provided for @vaultFromTime.
  ///
  /// In en, this message translates to:
  /// **'from {time}'**
  String vaultFromTime(String time);

  /// No description provided for @vaultCoachSeat.
  ///
  /// In en, this message translates to:
  /// **'coach {coach}, seat {seat}'**
  String vaultCoachSeat(String coach, String seat);

  /// No description provided for @vaultSeatIs.
  ///
  /// In en, this message translates to:
  /// **'seat {seat}'**
  String vaultSeatIs(String seat);

  /// No description provided for @vaultCodeIs.
  ///
  /// In en, this message translates to:
  /// **'code {code}'**
  String vaultCodeIs(String code);

  /// No description provided for @vaultFlightLeg.
  ///
  /// In en, this message translates to:
  /// **'Flight {number} · {from} → {to}'**
  String vaultFlightLeg(String number, String from, String to);

  /// No description provided for @vaultSoldFor.
  ///
  /// In en, this message translates to:
  /// **'Sold on {who} · {money}'**
  String vaultSoldFor(String who, String money);

  /// No description provided for @vaultSoldOnly.
  ///
  /// In en, this message translates to:
  /// **'Sold on {who}'**
  String vaultSoldOnly(String who);

  /// No description provided for @vaultSaleOnWay.
  ///
  /// In en, this message translates to:
  /// **'On its way'**
  String get vaultSaleOnWay;

  /// No description provided for @vaultSaleReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get vaultSaleReceived;

  /// No description provided for @vaultPaidOut.
  ///
  /// In en, this message translates to:
  /// **'Paid out'**
  String get vaultPaidOut;

  /// No description provided for @vaultCanGoBack.
  ///
  /// In en, this message translates to:
  /// **'Can still go back'**
  String get vaultCanGoBack;

  /// No description provided for @vaultUnderWarranty.
  ///
  /// In en, this message translates to:
  /// **'Under warranty'**
  String get vaultUnderWarranty;

  /// No description provided for @vaultDaysToReturn.
  ///
  /// In en, this message translates to:
  /// **'{who} · {days} days to return'**
  String vaultDaysToReturn(String who, int days);

  /// No description provided for @vaultBought.
  ///
  /// In en, this message translates to:
  /// **'bought {day}'**
  String vaultBought(String day);

  /// No description provided for @vaultWarrantyTo.
  ///
  /// In en, this message translates to:
  /// **'Warranty {month}'**
  String vaultWarrantyTo(String month);

  /// No description provided for @vaultCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get vaultCodeCopied;

  /// No description provided for @vaultCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get vaultCopyCode;

  /// No description provided for @vaultDocKind.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, payslip{Payslip} statement{Statement} tax{Tax form} contract{Contract} other{Document}}'**
  String vaultDocKind(String kind);

  /// No description provided for @vaultOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get vaultOpenFile;

  /// No description provided for @vaultBookingsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 booking} other{{count} bookings}}'**
  String vaultBookingsCount(int count);

  /// No description provided for @vaultDocumentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 document} other{{count} documents}}'**
  String vaultDocumentsCount(int count);

  /// No description provided for @vaultCategoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here right now.'**
  String get vaultCategoryEmpty;

  /// No description provided for @vaultFlagged.
  ///
  /// In en, this message translates to:
  /// **'needs you'**
  String get vaultFlagged;

  /// No description provided for @suggestWroteTo.
  ///
  /// In en, this message translates to:
  /// **'Wrote to'**
  String get suggestWroteTo;

  /// No description provided for @suggestWroteToYou.
  ///
  /// In en, this message translates to:
  /// **'Wrote to you'**
  String get suggestWroteToYou;

  /// No description provided for @readerEmptyTap.
  ///
  /// In en, this message translates to:
  /// **'Tap a message to read it.'**
  String get readerEmptyTap;

  /// No description provided for @noticeAwayTitle.
  ///
  /// In en, this message translates to:
  /// **'While you were away'**
  String get noticeAwayTitle;

  /// No description provided for @noticeAwayEmails.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 email} other{{count} emails}}'**
  String noticeAwayEmails(int count);

  /// No description provided for @noticeAwayPeople.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 from a person} other{{count} from people}}'**
  String noticeAwayPeople(int count);

  /// No description provided for @quietWeekends.
  ///
  /// In en, this message translates to:
  /// **'Weekends, all day'**
  String get quietWeekends;

  /// No description provided for @quietWeekendsHint.
  ///
  /// In en, this message translates to:
  /// **'Saturday and Sunday'**
  String get quietWeekendsHint;

  /// No description provided for @quietWhile.
  ///
  /// In en, this message translates to:
  /// **'While quiet'**
  String get quietWhile;

  /// No description provided for @quietWhileHint.
  ///
  /// In en, this message translates to:
  /// **'No notices sums up at the end'**
  String get quietWhileHint;

  /// No description provided for @quietNoSound.
  ///
  /// In en, this message translates to:
  /// **'No sound'**
  String get quietNoSound;

  /// No description provided for @quietNoNotices.
  ///
  /// In en, this message translates to:
  /// **'No notices'**
  String get quietNoNotices;

  /// No description provided for @quietRingsAsUsual.
  ///
  /// In en, this message translates to:
  /// **'{address} · rings as usual'**
  String quietRingsAsUsual(String address);

  /// No description provided for @quietAccountsHint.
  ///
  /// In en, this message translates to:
  /// **'Accounts switched off ring as usual in the quiet hours.'**
  String get quietAccountsHint;

  /// No description provided for @languageName.
  ///
  /// In en, this message translates to:
  /// **'{code, select, ar{Arabic} bg{Bulgarian} ca{Catalan} cs{Czech} zh{Chinese} da{Danish} de{German} el{Greek} en{English} et{Estonian} fi{Finnish} fr{French} he{Hebrew} hi{Hindi} hr{Croatian} hu{Hungarian} id{Indonesian} it{Italian} ja{Japanese} ko{Korean} lt{Lithuanian} lv{Latvian} nl{Dutch} nb{Norwegian} pl{Polish} pt{Portuguese} ro{Romanian} ru{Russian} sk{Slovak} sl{Slovenian} es{Spanish} sr{Serbian} sv{Swedish} th{Thai} tr{Turkish} uk{Ukrainian} vi{Vietnamese} other{{code}}}'**
  String languageName(String code);

  /// No description provided for @translateWrittenIn.
  ///
  /// In en, this message translates to:
  /// **'Written in {language}'**
  String translateWrittenIn(String language);

  /// No description provided for @translateAction.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translateAction;

  /// No description provided for @translateGetting.
  ///
  /// In en, this message translates to:
  /// **'Getting {from}–{to}'**
  String translateGetting(String from, String to);

  /// No description provided for @translateGettingSize.
  ///
  /// In en, this message translates to:
  /// **'Getting {from}–{to} · {size}'**
  String translateGettingSize(String from, String to, String size);

  /// No description provided for @translating.
  ///
  /// In en, this message translates to:
  /// **'Translating…'**
  String get translating;

  /// No description provided for @translatedFrom.
  ///
  /// In en, this message translates to:
  /// **'Translated from {language} · on this device'**
  String translatedFrom(String language);

  /// No description provided for @translatedShort.
  ///
  /// In en, this message translates to:
  /// **'Translated'**
  String get translatedShort;

  /// No description provided for @translateShowOriginal.
  ///
  /// In en, this message translates to:
  /// **'Show original'**
  String get translateShowOriginal;

  /// No description provided for @translateOriginalShort.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get translateOriginalShort;

  /// Snackbar when the system's language download was closed without downloading.
  ///
  /// In en, this message translates to:
  /// **'To translate, download {from} and {to} first.'**
  String translateNeedsDownload(String from, String to);

  /// No description provided for @translateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t translate this email. Try again.'**
  String get translateFailed;

  /// No description provided for @appearanceTranslateInto.
  ///
  /// In en, this message translates to:
  /// **'Translate into'**
  String get appearanceTranslateInto;

  /// No description provided for @translateIntoApp.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get translateIntoApp;

  /// No description provided for @translateIntoHint.
  ///
  /// In en, this message translates to:
  /// **'Emails in other languages offer Translate. It happens on this device.'**
  String get translateIntoHint;

  /// No description provided for @translatePair.
  ///
  /// In en, this message translates to:
  /// **'{from} → {to}'**
  String translatePair(String from, String to);

  /// No description provided for @translateRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get translateRemove;

  /// No description provided for @translateRemovePair.
  ///
  /// In en, this message translates to:
  /// **'Remove {pair}'**
  String translateRemovePair(String pair);

  /// No description provided for @printEmail.
  ///
  /// In en, this message translates to:
  /// **'Print…'**
  String get printEmail;

  /// No description provided for @printTooltip.
  ///
  /// In en, this message translates to:
  /// **'Print… {keys}'**
  String printTooltip(String keys);

  /// No description provided for @printOrSavePdf.
  ///
  /// In en, this message translates to:
  /// **'Print or save as PDF'**
  String get printOrSavePdf;

  /// No description provided for @reportSpam.
  ///
  /// In en, this message translates to:
  /// **'Report spam'**
  String get reportSpam;

  /// No description provided for @reportedSpamMany.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Reported as spam} other{{count} conversations reported as spam}}'**
  String reportedSpamMany(int count);

  /// No description provided for @notSpam.
  ///
  /// In en, this message translates to:
  /// **'Not spam'**
  String get notSpam;

  /// No description provided for @notSpamMany.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Moved to Inbox} other{{count} conversations moved to Inbox}}'**
  String notSpamMany(int count);

  /// No description provided for @spamFolder.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get spamFolder;

  /// No description provided for @printDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get printDate;

  /// No description provided for @printAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments: {files}'**
  String printAttachments(String files);

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & feedback'**
  String get helpTitle;

  /// No description provided for @helpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Report a problem or suggest an idea. Nothing is sent without you.'**
  String get helpSubtitle;

  /// No description provided for @reportProblem.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get reportProblem;

  /// No description provided for @reportThisProblem.
  ///
  /// In en, this message translates to:
  /// **'Report this problem'**
  String get reportThisProblem;

  /// No description provided for @reportCantAddAccount.
  ///
  /// In en, this message translates to:
  /// **'Can’t add my account'**
  String get reportCantAddAccount;

  /// No description provided for @suggestIdea.
  ///
  /// In en, this message translates to:
  /// **'Suggest an idea'**
  String get suggestIdea;

  /// No description provided for @shakeToReport.
  ///
  /// In en, this message translates to:
  /// **'Shake to report'**
  String get shakeToReport;

  /// No description provided for @shakeToReportHint.
  ///
  /// In en, this message translates to:
  /// **'Shake the phone on any screen'**
  String get shakeToReportHint;

  /// No description provided for @yourReports.
  ///
  /// In en, this message translates to:
  /// **'Your reports'**
  String get yourReports;

  /// No description provided for @reportNone.
  ///
  /// In en, this message translates to:
  /// **'No reports yet.'**
  String get reportNone;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportTitle;

  /// No description provided for @reportKindProblem.
  ///
  /// In en, this message translates to:
  /// **'Problem'**
  String get reportKindProblem;

  /// No description provided for @reportKindIdea.
  ///
  /// In en, this message translates to:
  /// **'Idea'**
  String get reportKindIdea;

  /// No description provided for @reportTitleField.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get reportTitleField;

  /// No description provided for @reportTitleHint.
  ///
  /// In en, this message translates to:
  /// **'In a few words'**
  String get reportTitleHint;

  /// No description provided for @reportProblemField.
  ///
  /// In en, this message translates to:
  /// **'What happened'**
  String get reportProblemField;

  /// No description provided for @reportIdeaField.
  ///
  /// In en, this message translates to:
  /// **'What and why'**
  String get reportIdeaField;

  /// No description provided for @reportDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'What you did, and what you expected'**
  String get reportDescriptionHint;

  /// No description provided for @reportScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Screenshot of this screen'**
  String get reportScreenshot;

  /// No description provided for @reportScreenshotWindow.
  ///
  /// In en, this message translates to:
  /// **'Screenshot of this window'**
  String get reportScreenshotWindow;

  /// No description provided for @reportScreenshotOff.
  ///
  /// In en, this message translates to:
  /// **'Off: it may show your mail'**
  String get reportScreenshotOff;

  /// No description provided for @reportScreenshotOn.
  ///
  /// In en, this message translates to:
  /// **'Tap the picture to hide parts'**
  String get reportScreenshotOn;

  /// No description provided for @reportLog.
  ///
  /// In en, this message translates to:
  /// **'App log'**
  String get reportLog;

  /// No description provided for @reportLogHint.
  ///
  /// In en, this message translates to:
  /// **'No addresses or subjects'**
  String get reportLogHint;

  /// No description provided for @reportDevice.
  ///
  /// In en, this message translates to:
  /// **'Device and app info'**
  String get reportDevice;

  /// No description provided for @reportDeviceHint.
  ///
  /// In en, this message translates to:
  /// **'Version, model, language'**
  String get reportDeviceHint;

  /// No description provided for @reportAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get reportAlways;

  /// No description provided for @reportSeeSent.
  ///
  /// In en, this message translates to:
  /// **'See what\'s sent'**
  String get reportSeeSent;

  /// No description provided for @reportSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get reportSend;

  /// No description provided for @reportQueued.
  ///
  /// In en, this message translates to:
  /// **'Report queued'**
  String get reportQueued;

  /// No description provided for @reportNotKept.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t keep the report'**
  String get reportNotKept;

  /// No description provided for @reportWhatsSent.
  ///
  /// In en, this message translates to:
  /// **'What\'s sent'**
  String get reportWhatsSent;

  /// No description provided for @reportSectionReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportSectionReport;

  /// No description provided for @reportSectionDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get reportSectionDevice;

  /// No description provided for @reportSectionScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Screenshot'**
  String get reportSectionScreenshot;

  /// No description provided for @reportHideParts.
  ///
  /// In en, this message translates to:
  /// **'Hide parts'**
  String get reportHideParts;

  /// No description provided for @reportDragToBlur.
  ///
  /// In en, this message translates to:
  /// **'Drag to blur'**
  String get reportDragToBlur;

  /// No description provided for @reportDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get reportDone;

  /// No description provided for @reportStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get reportStatusQueued;

  /// No description provided for @reportStatusSending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get reportStatusSending;

  /// No description provided for @reportStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get reportStatusFailed;

  /// No description provided for @reportStatusEmailed.
  ///
  /// In en, this message translates to:
  /// **'Emailed'**
  String get reportStatusEmailed;

  /// No description provided for @reportWaitOffline.
  ///
  /// In en, this message translates to:
  /// **'waiting for a network'**
  String get reportWaitOffline;

  /// No description provided for @reportWaitTurn.
  ///
  /// In en, this message translates to:
  /// **'goes in a moment'**
  String get reportWaitTurn;

  /// No description provided for @reportWaitAt.
  ///
  /// In en, this message translates to:
  /// **'goes at {time}'**
  String reportWaitAt(String time);

  /// No description provided for @reportWaitPaused.
  ///
  /// In en, this message translates to:
  /// **'goes later today or tomorrow'**
  String get reportWaitPaused;

  /// No description provided for @reportTapRetry.
  ///
  /// In en, this message translates to:
  /// **'tap to try again'**
  String get reportTapRetry;

  /// No description provided for @reportTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get reportTryAgain;

  /// No description provided for @reportByEmail.
  ///
  /// In en, this message translates to:
  /// **'Send by email instead'**
  String get reportByEmail;

  /// No description provided for @reportDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get reportDelete;

  /// No description provided for @reportOptions.
  ///
  /// In en, this message translates to:
  /// **'Report options'**
  String get reportOptions;

  /// No description provided for @crashLine.
  ///
  /// In en, this message translates to:
  /// **'Piuma closed unexpectedly. Send a report?'**
  String get crashLine;

  /// No description provided for @crashReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get crashReport;

  /// No description provided for @crashDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get crashDismiss;

  /// No description provided for @reportStatusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent #{number}'**
  String reportStatusSent(int number);

  /// No description provided for @reportSectionLog.
  ///
  /// In en, this message translates to:
  /// **'App log · {lines, plural, =1{1 line} other{{lines} lines}}'**
  String reportSectionLog(int lines);

  /// No description provided for @reportShown.
  ///
  /// In en, this message translates to:
  /// **'{title}, {status}'**
  String reportShown(String title, String status);

  /// No description provided for @paletteHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get paletteHelp;

  /// No description provided for @awayTitle.
  ///
  /// In en, this message translates to:
  /// **'Away message'**
  String get awayTitle;

  /// No description provided for @awayNote.
  ///
  /// In en, this message translates to:
  /// **'Replies for you, even with the app closed'**
  String get awayNote;

  /// No description provided for @awayFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get awayFrom;

  /// No description provided for @awayToInline.
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get awayToInline;

  /// No description provided for @awayTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get awayTo;

  /// No description provided for @awaySubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get awaySubject;

  /// No description provided for @awayMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get awayMessage;

  /// No description provided for @awayEndsNote.
  ///
  /// In en, this message translates to:
  /// **'Ends by itself after the last day. Leave \"to\" empty to keep it on until you turn it off.'**
  String get awayEndsNote;

  /// No description provided for @awaySubjectUntil.
  ///
  /// In en, this message translates to:
  /// **'Away until {date}'**
  String awaySubjectUntil(String date);

  /// No description provided for @awaySubjectPlain.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get awaySubjectPlain;

  /// No description provided for @awayBodyUntil.
  ///
  /// In en, this message translates to:
  /// **'Hi, I\'m away until {date} and will reply when I\'m back.'**
  String awayBodyUntil(String date);

  /// No description provided for @awayBodyPlain.
  ///
  /// In en, this message translates to:
  /// **'Hi, I\'m away and will reply when I\'m back.'**
  String get awayBodyPlain;

  /// No description provided for @awayToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get awayToday;

  /// No description provided for @awayNoEnd.
  ///
  /// In en, this message translates to:
  /// **'No end'**
  String get awayNoEnd;

  /// No description provided for @awayPickFrom.
  ///
  /// In en, this message translates to:
  /// **'First day'**
  String get awayPickFrom;

  /// No description provided for @awayPickTo.
  ///
  /// In en, this message translates to:
  /// **'Last day'**
  String get awayPickTo;

  /// No description provided for @awayKeepOn.
  ///
  /// In en, this message translates to:
  /// **'Keep it on until I turn it off'**
  String get awayKeepOn;

  /// No description provided for @awayOtherFilters.
  ///
  /// In en, this message translates to:
  /// **'Can\'t turn on alongside your existing filters. Turn them off on the server first.'**
  String get awayOtherFilters;

  /// No description provided for @awayUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This server no longer takes an away message.'**
  String get awayUnsupported;

  /// No description provided for @awayOffline.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Try again in a moment.'**
  String get awayOffline;

  /// No description provided for @awayLineUntil.
  ///
  /// In en, this message translates to:
  /// **'Away message on for {account} until {date}'**
  String awayLineUntil(String account, String date);

  /// No description provided for @awayLineOn.
  ///
  /// In en, this message translates to:
  /// **'Away message on for {account}'**
  String awayLineOn(String account);

  /// No description provided for @awayTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get awayTurnOff;

  /// No description provided for @awayRowOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get awayRowOff;

  /// No description provided for @awayRowOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get awayRowOn;

  /// No description provided for @awayRowUntil.
  ///
  /// In en, this message translates to:
  /// **'On until {date}'**
  String awayRowUntil(String date);

  /// No description provided for @featuresSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off what you don\'t use. It goes away everywhere, and nothing is deleted.'**
  String get featuresSubtitle;

  /// No description provided for @featuresZones.
  ///
  /// In en, this message translates to:
  /// **'Zones'**
  String get featuresZones;

  /// No description provided for @featuresOnDevice.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get featuresOnDevice;

  /// No description provided for @featuresOnDeviceNote.
  ///
  /// In en, this message translates to:
  /// **'Nothing here ever leaves the device.'**
  String get featuresOnDeviceNote;

  /// No description provided for @featureNewslettersHint.
  ///
  /// In en, this message translates to:
  /// **'Newsletters in their own list, to read like a magazine'**
  String get featureNewslettersHint;

  /// No description provided for @featureNewslettersOff.
  ///
  /// In en, this message translates to:
  /// **'Off · newsletters arrive in the inbox like any email'**
  String get featureNewslettersOff;

  /// No description provided for @featureVaultHint.
  ///
  /// In en, this message translates to:
  /// **'Payments, parcels, trips and deadlines as cards'**
  String get featureVaultHint;

  /// No description provided for @featureVaultOff.
  ///
  /// In en, this message translates to:
  /// **'Off · these emails stay as they are, with no cards or notices'**
  String get featureVaultOff;

  /// No description provided for @featureAttachmentsHint.
  ///
  /// In en, this message translates to:
  /// **'Every file you received, in one place'**
  String get featureAttachmentsHint;

  /// No description provided for @featureAttachmentsOff.
  ///
  /// In en, this message translates to:
  /// **'Off · files stay in their emails, and search still finds them'**
  String get featureAttachmentsOff;

  /// No description provided for @featureInShortHint.
  ///
  /// In en, this message translates to:
  /// **'The gist of long conversations, above the first email'**
  String get featureInShortHint;

  /// No description provided for @featureInShortOff.
  ///
  /// In en, this message translates to:
  /// **'Off · conversations open without the summary'**
  String get featureInShortOff;

  /// No description provided for @featureTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get featureTranslate;

  /// No description provided for @featureTranslateHint.
  ///
  /// In en, this message translates to:
  /// **'Offers to translate emails written in other languages'**
  String get featureTranslateHint;

  /// No description provided for @featureTranslateOff.
  ///
  /// In en, this message translates to:
  /// **'Off · no offer to translate, and no language is downloaded'**
  String get featureTranslateOff;

  /// No description provided for @featureFoundDates.
  ///
  /// In en, this message translates to:
  /// **'Dates in emails'**
  String get featureFoundDates;

  /// No description provided for @featureFoundDatesHint.
  ///
  /// In en, this message translates to:
  /// **'Add to calendar for dates and times found in the text'**
  String get featureFoundDatesHint;

  /// No description provided for @featureFoundDatesOff.
  ///
  /// In en, this message translates to:
  /// **'Off · invites still show their card'**
  String get featureFoundDatesOff;

  /// Screen reader action in an open email on the phone: go to the next email in the list.
  ///
  /// In en, this message translates to:
  /// **'Next email'**
  String get nextEmail;

  /// Screen reader action: go to the email before in the list.
  ///
  /// In en, this message translates to:
  /// **'Previous email'**
  String get previousEmail;

  /// Settings › Appearance: heading of the app's language picker
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get appearanceLanguage;

  /// Language picker choice: follow the device's language, English where the app doesn't speak it
  ///
  /// In en, this message translates to:
  /// **'Device language'**
  String get languageDevice;

  /// No description provided for @senderLooksLike.
  ///
  /// In en, this message translates to:
  /// **'{domain} looks like {like}, but it\'s a different address.'**
  String senderLooksLike(String domain, String like);

  /// No description provided for @senderBrand.
  ///
  /// In en, this message translates to:
  /// **'The name says {brand}, but the address is at {domain}.'**
  String senderBrand(String brand, String domain);

  /// No description provided for @senderDmarcFailed.
  ///
  /// In en, this message translates to:
  /// **'This email says it\'s from {domain}, but {domain} didn\'t send it.'**
  String senderDmarcFailed(String domain);

  /// No description provided for @senderDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get senderDetails;

  /// No description provided for @senderDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'What was checked'**
  String get senderDetailsTitle;

  /// No description provided for @senderSentBy.
  ///
  /// In en, this message translates to:
  /// **'Sent by'**
  String get senderSentBy;

  /// No description provided for @senderNotKnown.
  ///
  /// In en, this message translates to:
  /// **'Not known'**
  String get senderNotKnown;

  /// No description provided for @senderSignature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get senderSignature;

  /// No description provided for @senderSignatureNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get senderSignatureNone;

  /// No description provided for @senderDomainCheck.
  ///
  /// In en, this message translates to:
  /// **'Domain check'**
  String get senderDomainCheck;

  /// No description provided for @senderDomainCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed (DMARC)'**
  String get senderDomainCheckFailed;

  /// No description provided for @senderLooksLikeLabel.
  ///
  /// In en, this message translates to:
  /// **'Looks like'**
  String get senderLooksLikeLabel;

  /// No description provided for @senderLooksLikeValue.
  ///
  /// In en, this message translates to:
  /// **'{like}, {count, plural, =0{no emails from it} =1{1 email from it} other{{count} emails from it}}'**
  String senderLooksLikeValue(String like, int count);

  /// No description provided for @senderNameSays.
  ///
  /// In en, this message translates to:
  /// **'Name says'**
  String get senderNameSays;

  /// No description provided for @senderDetailsNote.
  ///
  /// In en, this message translates to:
  /// **'Worked out on this device from what your mail server wrote. Links in this email ask before they open.'**
  String get senderDetailsNote;

  /// No description provided for @impostorLinkBody.
  ///
  /// In en, this message translates to:
  /// **'This email may not be from who it says. The link goes to {real}.'**
  String impostorLinkBody(String real);

  /// No description provided for @updates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updates;

  /// No description provided for @updatesVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get updatesVersion;

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get upToDate;

  /// No description provided for @updatesAuto.
  ///
  /// In en, this message translates to:
  /// **'Piuma looks for new versions on its own'**
  String get updatesAuto;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updateChecking;

  /// No description provided for @checkedJustNow.
  ///
  /// In en, this message translates to:
  /// **'Checked just now'**
  String get checkedJustNow;

  /// No description provided for @checkedMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Checked 1 minute ago} other{Checked {count} minutes ago}}'**
  String checkedMinutesAgo(int count);

  /// No description provided for @checkedHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Checked 1 hour ago} other{Checked {count} hours ago}}'**
  String checkedHoursAgo(int count);

  /// No description provided for @checkedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Checked yesterday} other{Checked {count} days ago}}'**
  String checkedDaysAgo(int count);

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {version} · {percent}%'**
  String updateDownloading(String version, int percent);

  /// No description provided for @updateDownloadedOf.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String updateDownloadedOf(String done, String total);

  /// No description provided for @updateReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready · {version}'**
  String updateReadyTitle(String version);

  /// No description provided for @updateGoesInOnRestart.
  ///
  /// In en, this message translates to:
  /// **'Goes in when Piuma restarts'**
  String get updateGoesInOnRestart;

  /// No description provided for @restart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get restart;

  /// No description provided for @updateCouldntCheck.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check'**
  String get updateCouldntCheck;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @seeWhatsNew.
  ///
  /// In en, this message translates to:
  /// **'See what\'s new'**
  String get seeWhatsNew;

  /// No description provided for @whatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get whatsNew;

  /// No description provided for @whatsNewVersion.
  ///
  /// In en, this message translates to:
  /// **'Piuma Mail {version}'**
  String whatsNewVersion(String version);

  /// No description provided for @updateKeepsMail.
  ///
  /// In en, this message translates to:
  /// **'Your mail and drafts are kept. Piuma closes and opens again in a few seconds.'**
  String get updateKeepsMail;

  /// No description provided for @restartNow.
  ///
  /// In en, this message translates to:
  /// **'Restart now'**
  String get restartNow;

  /// No description provided for @updateReadyLine.
  ///
  /// In en, this message translates to:
  /// **'Update ready · {version}'**
  String updateReadyLine(String version);

  /// No description provided for @updatedTo.
  ///
  /// In en, this message translates to:
  /// **'Updated to {version}'**
  String updatedTo(String version);

  /// No description provided for @swipeHintArchiveSnooze.
  ///
  /// In en, this message translates to:
  /// **'Swipe right to archive, left to snooze'**
  String get swipeHintArchiveSnooze;

  /// No description provided for @swipeHintArchive.
  ///
  /// In en, this message translates to:
  /// **'Swipe right to archive'**
  String get swipeHintArchive;

  /// No description provided for @formatting.
  ///
  /// In en, this message translates to:
  /// **'Formatting'**
  String get formatting;

  /// No description provided for @formatBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get formatBold;

  /// No description provided for @formatItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get formatItalic;

  /// No description provided for @formatLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get formatLink;

  /// No description provided for @formatBullets.
  ///
  /// In en, this message translates to:
  /// **'Bulleted list'**
  String get formatBullets;

  /// No description provided for @formatNumbers.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get formatNumbers;

  /// No description provided for @formatQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get formatQuote;

  /// No description provided for @linkAddressHint.
  ///
  /// In en, this message translates to:
  /// **'Paste or type an address'**
  String get linkAddressHint;

  /// No description provided for @linkAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get linkAdd;

  /// No description provided for @linkRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove link'**
  String get linkRemove;

  /// No description provided for @imagesOffBar.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 image is off, so {sender} can’t see when you open this.} other{{count} images are off, so {sender} can’t see when you open this.}}'**
  String imagesOffBar(int count, String sender);

  /// No description provided for @loadImages.
  ///
  /// In en, this message translates to:
  /// **'Load images'**
  String get loadImages;

  /// No description provided for @alwaysForSender.
  ///
  /// In en, this message translates to:
  /// **'Always for this sender'**
  String get alwaysForSender;

  /// No description provided for @cleanView.
  ///
  /// In en, this message translates to:
  /// **'Clean view'**
  String get cleanView;

  /// No description provided for @viewOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get viewOriginal;

  /// No description provided for @viewClean.
  ///
  /// In en, this message translates to:
  /// **'Clean'**
  String get viewClean;

  /// No description provided for @calGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar'**
  String get calGoogle;

  /// No description provided for @calGoogleSub.
  ///
  /// In en, this message translates to:
  /// **'Read events and availability with an iCal link'**
  String get calGoogleSub;

  /// No description provided for @calGoogleLabel.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar iCal address'**
  String get calGoogleLabel;

  /// No description provided for @calGoogleHint.
  ///
  /// In en, this message translates to:
  /// **'In Google Calendar on a computer: Settings › your calendar › Integrate calendar › Secret address in iCal format. Read-only; connects directly.'**
  String get calGoogleHint;

  /// No description provided for @bundledReleaseNotes.
  ///
  /// In en, this message translates to:
  /// **'## Mail, made light\n- Original email layouts with single-page scrolling and image controls\n- Formatting bar and full-editor switch in replies\n- Deliberate horizontal mail swipes\n- Sender warnings for brand impersonation and look-alike domains\n- Vault monthly CSV export with merchant VAT numbers'**
  String get bundledReleaseNotes;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'pt',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
