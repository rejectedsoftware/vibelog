module vibelog.internal.diskuto;

import vibelog.controller;
import vibelog.user;

import diskuto.commentstore : StoredComment;
import diskuto.commentstores.mongodb;
import diskuto.web : DiskutoWeb, registerDiskutoWeb;
import diskuto.settings : DiskutoSettings;
import diskuto.userstore : StoredUser, DiskutoUserStore;
import vibe.data.json : parseJsonString;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest;
import std.typecons : Nullable;

DiskutoWeb registerDiskuto(URLRouter router, VibeLogController ctrl)
{
	import antispam.antispam : AntispamState, SpamFilter;
	import antispam.filters.bayes : BayesSpamFilter;
	AntispamState.registerFilter("bayes", () => cast(SpamFilter)new BayesSpamFilter);

	auto dsettings = new DiskutoSettings;
	dsettings.commentStore = ctrl.diskuto;
	dsettings.userStore = new UserStore(ctrl);
	dsettings.antispam = parseJsonString(`[{"filter": "bayes", "settings": {}}]`);
	return router.registerDiskutoWeb(dsettings);
}

private final class UserStore : DiskutoUserStore {
	private {
		VibeLogController m_ctrl;
	}

	this(VibeLogController ctrl)
	{
		m_ctrl = ctrl;
	}

	override Nullable!StoredUser getLoggedInUser(HTTPServerRequest req)
	@trusted {
		try {
			if (req.session) {
				auto usr = req.session.get("vibelog.loggedInUser", "");
				if (usr.length)
					return Nullable!StoredUser(toStoredUser(m_ctrl.db.getUserByName(usr)));
			}
		} catch (Exception e) {}
		return Nullable!StoredUser.init;
	}

	override Nullable!StoredUser getUserForEmail(string email)
	@trusted {
		try return Nullable!StoredUser(toStoredUser(m_ctrl.db.getUserByEmail(email)));
		catch (Exception e) { return Nullable!StoredUser.init; }
	}

	override StoredUser.Role getUserRole(StoredUser.ID user, string topic)
	@trusted {
		import std.algorithm.searching : startsWith;
		import vibe.data.bson : BsonObjectID;

		User dbuser;
		try {
			if (user.startsWith("vibelog-")) {
				auto user_id = BsonObjectID.fromString(user[8 .. $]);
				dbuser = m_ctrl.db.getUser(user_id);
				if (dbuser.inGroup("admin")) return StoredUser.Role.moderator;
			}
		} catch (Exception e) {}

		if (!topic.startsWith("vibelog-")) 
			return StoredUser.Role.member;

		try {
			auto post_id = BsonObjectID.fromString(topic[8 .. $]);
			auto post = m_ctrl.db.getPost(post_id);
			if (dbuser && dbuser.mayPostInCategory(post.category))
				return StoredUser.Role.moderator;
			return post.commentsAllowed ? StoredUser.Role.member : StoredUser.Role.reader;
		} catch (Exception e) {
			return StoredUser.Role.reader;
		}
	}

	private StoredUser toStoredUser(User usr)
	@safe {
		StoredUser ret;
		ret.id = "vibelog-" ~ () @trusted { return usr._id.toString(); } ();
		ret.name = usr.name;
		ret.email = usr.email;
		return ret;
	}
}
