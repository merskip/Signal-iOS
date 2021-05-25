//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "TSGroupThread.h"
#import "TSAttachmentStream.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSGroupThreadAvatarChangedNotification = @"TSGroupThreadAvatarChangedNotification";
NSString *const TSGroupThread_NotificationKey_UniqueId = @"TSGroupThread_NotificationKey_UniqueId";

@interface TSGroupThread ()

@property (nonatomic) TSGroupModel *groupModel;

@end

#pragma mark -

@implementation TSGroupThread

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
   conversationColorNameObsolete:(NSString *)conversationColorNameObsolete
                    creationDate:(nullable NSDate *)creationDate
              isArchivedObsolete:(BOOL)isArchivedObsolete
          isMarkedUnreadObsolete:(BOOL)isMarkedUnreadObsolete
            lastInteractionRowId:(int64_t)lastInteractionRowId
       lastVisibleSortIdObsolete:(uint64_t)lastVisibleSortIdObsolete
lastVisibleSortIdOnScreenPercentageObsolete:(double)lastVisibleSortIdOnScreenPercentageObsolete
         mentionNotificationMode:(TSThreadMentionNotificationMode)mentionNotificationMode
                    messageDraft:(nullable NSString *)messageDraft
          messageDraftBodyRanges:(nullable MessageBodyRanges *)messageDraftBodyRanges
          mutedUntilDateObsolete:(nullable NSDate *)mutedUntilDateObsolete
     mutedUntilTimestampObsolete:(uint64_t)mutedUntilTimestampObsolete
           shouldThreadBeVisible:(BOOL)shouldThreadBeVisible
                      groupModel:(TSGroupModel *)groupModel
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId
     conversationColorNameObsolete:conversationColorNameObsolete
                      creationDate:creationDate
                isArchivedObsolete:isArchivedObsolete
            isMarkedUnreadObsolete:isMarkedUnreadObsolete
              lastInteractionRowId:lastInteractionRowId
         lastVisibleSortIdObsolete:lastVisibleSortIdObsolete
lastVisibleSortIdOnScreenPercentageObsolete:lastVisibleSortIdOnScreenPercentageObsolete
           mentionNotificationMode:mentionNotificationMode
                      messageDraft:messageDraft
            messageDraftBodyRanges:messageDraftBodyRanges
            mutedUntilDateObsolete:mutedUntilDateObsolete
       mutedUntilTimestampObsolete:mutedUntilTimestampObsolete
             shouldThreadBeVisible:shouldThreadBeVisible];

    if (!self) {
        return self;
    }

    _groupModel = groupModel;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (MessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithGroupModelPrivate:(TSGroupModel *)groupModel transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(groupModel);
    OWSAssertDebug(groupModel.groupId.length > 0);
    for (SignalServiceAddress *address in groupModel.groupMembers) {
        OWSAssertDebug(address.isValid);
    }

    NSString *uniqueIdentifier = [[self class] threadIdForGroupId:groupModel.groupId transaction:transaction];
    self = [super initWithUniqueId:uniqueIdentifier];
    if (!self) {
        return self;
    }

    _groupModel = groupModel;

    return self;
}

+ (nullable instancetype)fetchWithGroupId:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *uniqueId = [self threadIdForGroupId:groupId transaction:transaction];
    return [TSGroupThread anyFetchGroupThreadWithUniqueId:uniqueId transaction:transaction];
}

- (NSArray<SignalServiceAddress *> *)recipientAddresses
{
    NSMutableArray<SignalServiceAddress *> *groupMembers = [self.groupModel.groupMembers mutableCopy];
    if (groupMembers == nil) {
        return @[];
    }

    [groupMembers removeObject:TSAccountManager.localAddress];

    return [groupMembers copy];
}

- (NSString *)groupNameOrDefault
{
    return self.groupModel.groupNameOrDefault;
}

+ (NSString *)defaultGroupName
{
    return NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
}

- (void)updateWithGroupModel:(TSGroupModel *)newGroupModel transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(newGroupModel);
    OWSAssertDebug(transaction);

    switch (newGroupModel.groupsVersion) {
        case GroupsVersionV1:
            OWSAssertDebug(newGroupModel.groupsVersion == self.groupModel.groupsVersion);
            break;
        case GroupsVersionV2:
            // Group version may be changing due to migration.
            break;
    }

    BOOL didAvatarChange = ![NSObject isNullableObject:newGroupModel.groupAvatarData
                                               equalTo:self.groupModel.groupAvatarData];

    [self anyUpdateGroupThreadWithTransaction:transaction
                                        block:^(TSGroupThread *thread) {
                                            if ([thread.groupModel isKindOfClass:TSGroupModelV2.class]) {
                                                if (![newGroupModel isKindOfClass:TSGroupModelV2.class]) {
                                                    // Can't downgrade a v2 group to a v1 group.
                                                    OWSFail(@"Invalid group model.");
                                                } else {
                                                    // Can't downgrade a v2 group to an earlier revision.
                                                    TSGroupModelV2 *oldGroupModelV2
                                                        = (TSGroupModelV2 *)thread.groupModel;
                                                    TSGroupModelV2 *newGroupModelV2 = (TSGroupModelV2 *)newGroupModel;
                                                    OWSAssert(oldGroupModelV2.revision <= newGroupModelV2.revision);
                                                }
                                            }

                                            thread.groupModel = [newGroupModel copy];
                                        }];

    if (didAvatarChange) {
        [transaction addAsyncCompletion:^{
            [self fireAvatarChangedNotification];
        }];
    }
}

- (void)fireAvatarChangedNotification
{
    OWSAssertIsOnMainThread();

    NSDictionary *userInfo = @{ TSGroupThread_NotificationKey_UniqueId : self.uniqueId };

    [[NSNotificationCenter defaultCenter] postNotificationName:TSGroupThreadAvatarChangedNotification
                                                        object:self.uniqueId
                                                      userInfo:userInfo];
}

- (void)anyWillRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    if (self.isGroupV2Thread) {
        OWSFailDebug(@"In normal usage we should only soft delete v2 groups.");
    }
    [super anyWillRemoveWithTransaction:transaction];
    [self updateGroupMemberRecordsWithTransaction:transaction];
}

#pragma mark -

- (void)anyWillInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillInsertWithTransaction:transaction];

    [self protectV2Migration:transaction];
    [self updateGroupMemberRecordsWithTransaction:transaction];
}

- (void)anyWillUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillUpdateWithTransaction:transaction];

    [self protectV2Migration:transaction];
    [self updateGroupMemberRecordsWithTransaction:transaction];
}

- (void)protectV2Migration:(SDSAnyWriteTransaction *)transaction
{
    if (self.groupModel.groupsVersion != GroupsVersionV1) {
        return;
    }

    [TSGroupThread ensureGroupIdMappingForGroupId:self.groupModel.groupId transaction:transaction];

    TSGroupThread *_Nullable databaseCopy = [TSGroupThread anyFetchGroupThreadWithUniqueId:self.uniqueId
                                                                               transaction:transaction];
    if (databaseCopy == nil) {
        return;
    }

    if (databaseCopy.groupModel.groupsVersion == GroupsVersionV2) {
        OWSFail(@"v1-to-v2 group migration can not be reversed.");
    }
}

- (void)updateWithInsertedMessage:(TSInteraction *)message transaction:(SDSAnyWriteTransaction *)transaction
{
    [super updateWithInsertedMessage:message transaction:transaction];

    SignalServiceAddress *_Nullable senderAddress;
    if ([message isKindOfClass:[TSOutgoingMessage class]]) {
        senderAddress = self.tsAccountManager.localAddress;
    } else if ([message isKindOfClass:[TSIncomingMessage class]]) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message;
        senderAddress = incomingMessage.authorAddress;
    }

    if (senderAddress) {
        TSGroupMember *_Nullable groupMember = [TSGroupMember groupMemberForAddress:senderAddress
                                                                    inGroupThreadId:self.uniqueId
                                                                        transaction:transaction];
        if (groupMember) {
            [groupMember updateWithLastInteractionTimestamp:message.timestamp transaction:transaction];
        } else {
            OWSFailDebug(@"Unexpectedly missing group member record");
        }
    }
}

@end

NS_ASSUME_NONNULL_END
