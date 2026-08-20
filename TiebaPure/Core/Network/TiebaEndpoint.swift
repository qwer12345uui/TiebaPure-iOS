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
    case forumInfo
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
            return Self.appBase.compatAppending(path: "/c/s/login")
        case .postingLogin:
            return Self.protobufBase.compatAppending(path: "/c/s/login")
        case .initNickname:
            return Self.appBase.compatAppending(path: "/c/s/initNickname")
        case .webMyInfo:
            return Self.base.compatAppending(path: "/mo/q/newmoindex")
        case .followedForums:
            return Self.appBase.compatAppending(path: "/c/f/forum/getforumlist")
        case .forumPageForm:
            return Self.appBase.compatAppending(path: "/c/f/frs/page")
        case .forumInfo:
            return Self.appBase.compatAppending(path: "/c/f/frs/frsBottom")
        case .personalized:
            return Self.base
                .compatAppending(path: "/c/f/excellent/personalized")
                .compatAppending(queryItems: [.init(name: "cmd", value: "309264")])
        case .frsPage:
            return Self.base
                .compatAppending(path: "/c/f/frs/page")
                .compatAppending(queryItems: [.init(name: "cmd", value: "301001")])
        case .pbPage:
            return Self.base
                .compatAppending(path: "/c/f/pb/page")
                .compatAppending(queryItems: [
                    .init(name: "cmd", value: "302001"),
                    .init(name: "format", value: "protobuf")
                ])
        case .pbFloor:
            return Self.base
                .compatAppending(path: "/c/f/pb/floor")
                .compatAppending(queryItems: [
                    .init(name: "cmd", value: "302002"),
                    .init(name: "format", value: "protobuf")
                ])
        case .searchThread:
            return Self.base.compatAppending(path: "/mo/q/search/thread")
        case .searchUser:
            return Self.base.compatAppending(path: "/mo/q/search/user")
        case .userProfile:
            return Self.protobufBase
                .compatAppending(path: "/c/u/user/profile")
                .compatAppending(queryItems: [
                    .init(name: "cmd", value: "303012"),
                    .init(name: "format", value: "protobuf")
                ])
        case .userThreads:
            return Self.protobufBase
                .compatAppending(path: "/c/u/feed/userpost")
                .compatAppending(queryItems: [
                    .init(name: "cmd", value: "303002"),
                    .init(name: "format", value: "protobuf")
                ])
        case .modifyProfile:
            return Self.socialBase.compatAppending(path: "/c/c/profile/modify")
        case .deleteOwnThread:
            return Self.appBase.compatAppending(path: "/c/c/bawu/delthread")
        case .followUser:
            return Self.socialBase.compatAppending(path: "/c/c/user/follow")
        case .unfollowUser:
            return Self.socialBase.compatAppending(path: "/c/c/user/unfollow")
        case .followedUsers:
            return Self.socialBase.compatAppending(path: "/c/u/follow/followList")
        case .followers:
            return Self.socialBase.compatAppending(path: "/c/u/fans/page")
        case .resolveForumID:
            // The www host answers this path with a 301 down to plain http,
            // which the client refuses to follow; the app host serves the same
            // JSON over https.
            return Self.appBase.compatAppending(path: "/f/commit/share/fnameShareApi")
        case .forumMembership:
            return Self.socialBase.compatAppending(path: "/c/f/forum/getUserForumLevelInfo")
        case .followForum:
            return Self.socialBase.compatAppending(path: "/c/c/forum/like")
        case .unfollowForum:
            return Self.socialBase.compatAppending(path: "/c/c/forum/unfavolike")
        case .signForum:
            return Self.appBase.compatAppending(path: "/c/c/forum/sign")
        case .threadStoreList:
            return Self.appBase.compatAppending(path: "/c/u/feed/threadStoreList")
        case .addThreadStore:
            return Self.appBase.compatAppending(path: "/c/c/post/addstore")
        case .removeThreadStore:
            return Self.appBase.compatAppending(path: "/c/c/post/rmstore")
        case .agreePost:
            return Self.socialBase.compatAppending(path: "/c/c/agree/opAgree")
        case .webTBS:
            return Self.base.compatAppending(path: "/dc/common/tbs")
        case .webAddThread:
            return Self.base.compatAppending(path: "/f/commit/thread/add")
        case let .webAddPost(timestamp):
            return Self.base
                .compatAppending(path: "/mo/q/apubpost")
                .compatAppending(queryItems: [.init(name: "_t", value: String(timestamp))])
        case let .webUploadPicture(nonce):
            return Self.base
                .compatAppending(path: "/mo/q/cooluploadpic")
                .compatAppending(queryItems: [
                    .init(name: "type", value: "ajax"),
                    .init(name: "r", value: nonce)
                ])
        case .addPost:
            return Self.protobufBase
                .compatAppending(path: "/c/c/post/add")
                .compatAppending(queryItems: [.init(name: "cmd", value: "309731")])
        case .uploadPicture:
            return Self.protobufBase.compatAppending(path: "/c/s/uploadPicture")
        }
    }
}
