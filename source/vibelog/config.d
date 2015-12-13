module vibelog.config;

import vibe.data.bson;

final class Config {
	BsonObjectID id;
	string name;
	string[] categories;
	string language = "en-us";
	string copyrightString;
	string mailServer;
	string feedTitle;
	string feedLink;
	string feedDescription;
	string feedImageTitle;
	string feedImageUrl;

	this()
	{
		id  = BsonObjectID.generate();
	}

	@property string[] groups() const { return ["admin"]; }

	bool hasCategory(string cat) const {
		foreach( c; categories )
			if( c == cat )
				return true;
		return false;
	}

	static Config fromBson(Bson bson)
	{
		auto ret = new Config;
		ret.id = bson["_id"].opt!BsonObjectID();
		ret.name = bson["name"].opt!string();
		foreach( grp; cast(Bson[])bson["categories"] )
			ret.categories ~= grp.opt!string();
		ret.language = bson["language"].opt!string(language.init);
		ret.copyrightString = bson["copyrightString"].opt!string();
		ret.mailServer = bson["mailServer"].opt!string();
		ret.feedTitle = bson["feedTitle"].opt!string();
		ret.feedLink = bson["feedLink"].opt!string();
		ret.feedDescription = bson["feedDescription"].opt!string();
		ret.feedImageTitle = bson["feedImageTitle"].opt!string();
		ret.feedImageUrl = bson["feedImageUrl"].opt!string();
		return ret;
	}

	Bson toBson()
	const {
		Bson[] bcategories;
		foreach( grp; categories )
			bcategories ~= Bson(grp);

		// Create a default category if none is specified
		if(bcategories.length < 1)
		{
			bcategories ~= Bson("general");
		}

		// Could use a switch here
		Bson[string] ret;
		ret["_id"] = Bson(id);
		ret["name"] = Bson(name);
		ret["categories"] = Bson(bcategories);
		ret["language"] = Bson(language);
		ret["copyrightString"] = Bson(copyrightString);
		ret["mailServer"] = Bson(mailServer);
		ret["feedTitle"] = Bson(feedTitle);
		ret["feedLink"] = Bson(feedLink);
		ret["feedDescription"] = Bson(feedDescription);
		ret["feedImageTitle"] = Bson(feedImageTitle);
		ret["feedImageUrl"] = Bson(feedImageUrl);

		return Bson(ret);
	}
}
