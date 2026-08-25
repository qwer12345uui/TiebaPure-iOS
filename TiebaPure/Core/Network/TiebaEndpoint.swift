import Foundation

enum TiebaEndpoint {
    static let base = URL(string: "https://tieba.baidu.com")!
    static let appBase = URL(string: "https://c.tieba.baidu.com")!
    static let protobufBase = URL(string: "https://tiebac.baidu.com")!
    static let socialBase = URL(string: "https://tiebac.baidu.com")!

    case login
    case postingLogin
    case initNickname
    case webMyInfo
    case followedForums
    case forumPageForm
    case personalized
    case frsPage
    case pbPage
    case pbFloor
    case searchThread
    case searchUser
    case userProfile
    case userThreads
    case modifyProfile
    case deleteOwnThread
    case followUser
    case unfollowUser
    case followedUsers
    case followers
    case resolveForumID
    case forumMembership
    case followForum
    case unfollowForum
    case signForum
    case threadStoreList
    case addThreadStore
    case removeThreadStore
    case agreePost
    case webAddThread
    case webAddPost(timestamp: Int64)
    case webUploadPicture(nonce: String)
    case addPost
    case uploadPicture

    var url: URL {
        switch self {
        case .login:
            return Self.appBase.appendingLegacyPath( "/c/s/login")
        case .postingLogin:
            return Self.protobufBase.appendingLegacyPath( "/c/s/login")
        case .initNickname:
            return Self.appBase.appendingLegacyPath( "/c/s/initNickname")
        case .webMyInfo:
            return Self.base.appendingLegacyPath( "/mo/q/newmoindex")
        case .followedForums:
            return Self.appBase.appendingLegacyPath( "/c/f/forum/getforumlist")
        case .forumPageForm:
            return Self.appBase.appendingLegacyPath( "/c/f/frs/page")
        case .personalized:
            return Self.base
                .appendingLegacyPath( "/c/f/excellent/personalized")
                .appendingLegacyQueryItems( [.init(name: "cmd", value: "309264")])
        case .frsPage:
            return Self.base
                .appendingLegacyPath( "/c/f/frs/page")
                .appendingLegacyQueryItems( [.init(name: "cmd", value: "301001")])
        case .pbPage:
            return Self.base
                .appendingLegacyPath( "/c/f/pb/page")
                .appendingLegacyQueryItems( [
                    .init(name: "cmd", value: "302001"),
                    .init(name: "format", value: "protobuf")
                ])
        case .pbFloor:
            return Self.base
                .appendingLegacyPath( "/c/f/pb/floor")
                .appendingLegacyQueryItems( [
                    .init(name: "cmd", value: "302002"),
                    .init(name: "format", value: "protobuf")
                ])
        case .searchThread:
            return Self.base.appendingLegacyPath( "/mo/q/search/thread")
        case .searchUser:
            return Self.base.appendingLegacyPath( "/mo/q/search/user")
        case .userProfile:
            return Self.protobufBase
                .appendingLegacyPath( "/c/u/user/profile")
                .appendingLegacyQueryItems( [
                    .init(name: "cmd", value: "303012"),
                    .init(name: "format", value: "protobuf")
                ])
        case .userThreads:
            return Self.protobufBase
                .appendingLegacyPath( "/c/u/feed/userpost")
                .appendingLegacyQueryItems( [
                    .init(name: "cmd", value: "303002"),
                    .init(name: "format", value: "protobuf")
                ])
        case .modifyProfile:
            return Self.socialBase.appendingLegacyPath( "/c/c/profile/modify")
        case .deleteOwnThread:
            return Self.appBase.appendingLegacyPath( "/c/c/bawu/delthread")
        case .followUser:
            return Self.socialBase.appendingLegacyPath( "/c/c/user/follow")
        case .unfollowUser:
            return Self.socialBase.appendingLegacyPath( "/c/c/user/unfollow")
        case .followedUsers:
            return Self.socialBase.appendingLegacyPath( "/c/u/follow/followList")
        case .followers:
            return Self.socialBase.appendingLegacyPath( "/c/u/fans/page")
        case .resolveForumID:
            // The www host answers this path with a 301 down to plain http,
            // which the client refuses to follow; the app host serves the same
            // JSON over https.
            return Self.appBase.appendingLegacyPath( "/f/commit/share/fnameShareApi")
        case .forumMembership:
            return Self.socialBase.appendingLegacyPath( "/c/f/forum/getUserForumLevelInfo")
        case .followForum:
            return Self.socialBase.appendingLegacyPath( "/c/c/forum/like")
        case .unfollowForum:
            return Self.socialBase.appendingLegacyPath( "/c/c/forum/unfavolike")
        case .signForum:
            return Self.appBase.appendingLegacyPath( "/c/c/forum/sign")
        case .threadStoreList:
            return Self.appBase.appendingLegacyPath( "/c/u/feed/threadStoreList")
        case .addThreadStore:
            return Self.appBase.appendingLegacyPath( "/c/c/post/addstore")
        case .removeThreadStore:
            return Self.appBase.appendingLegacyPath( "/c/c/post/rmstore")
        case .agreePost:
            return Self.socialBase.appendingLegacyPath( "/c/c/agree/opAgree")
        case .webAddThread:
            return Self.base.appendingLegacyPath( "/f/commit/thread/add")
        case let .webAddPost(timestamp):
            return Self.base
                .appendingLegacyPath( "/mo/q/apubpost")
                .appendingLegacyQueryItems( [.init(name: "_t", value: String(timestamp))])
        case let .webUploadPicture(nonce):
            return Self.base
                .appendingLegacyPath( "/mo/q/cooluploadpic")
                .appendingLegacyQueryItems( [
                    .init(name: "type", value: "ajax"),
                    .init(name: "r", value: nonce)
                ])
        case .addPost:
            return Self.protobufBase
                .appendingLegacyPath( "/c/c/post/add")
                .appendingLegacyQueryItems( [.init(name: "cmd", value: "309731")])
        case .uploadPicture:
            return Self.protobufBase.appendingLegacyPath( "/c/s/uploadPicture")
        }
    }
}
