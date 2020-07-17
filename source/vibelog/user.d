module vibelog.user;

import vibe.data.bson;
import vibe.textfilter.markdown;
import vibe.textfilter.html;

import std.array;
import std.base64;
import std.conv;
import std.exception;
import std.random;
public import std.datetime;


class User {
	BsonObjectID _id;
	string username;
	string name;
	string email;
	string password;
	string[] groups;
	string[] allowedCategories;

	this()
	{
		_id = BsonObjectID.generate();
	}

	bool inGroup(string group) const {
		foreach( g; groups )
			if( g == group )
				return true;
		return false;
	}

	bool isConfigAdmin() const { return inGroup("admin"); }
	bool isUserAdmin() const { return inGroup("admin"); }
	bool isPostAdmin() const { return inGroup("admin"); }
	bool mayPostInCategory(string category){
		if( isPostAdmin() ) return true;
		foreach( c; allowedCategories )
			if( c == category )
				return true;
		return false;
	}

	static User fromBson(Bson bson)
	{
		auto ret = new User;
		ret._id = cast(BsonObjectID)bson["_id"];
		ret.username = cast(string)bson["username"];
		ret.name = cast(string)bson["name"];
		ret.email = cast(string)bson["email"];
		ret.password = cast(string)bson["password"];
		foreach( grp; cast(Bson[])bson["groups"] )
			ret.groups ~= cast(string)grp;
		foreach( cat; cast(Bson[])bson["allowedCategories"] )
			ret.allowedCategories ~= cast(string)cat;
		return ret;
	}
	
	Bson toBson()
	const {
		Bson[] bgroups;
		foreach( grp; groups )
			bgroups ~= Bson(grp);

		Bson[] bcats;
		foreach( cat; allowedCategories )
			bcats ~= Bson(cat);

		Bson[string] ret;
		ret["_id"] = Bson(_id);
		ret["username"] = Bson(username);
		ret["name"] = Bson(name);
		ret["email"] = Bson(email);
		ret["password"] = Bson(password);
		ret["groups"] = Bson(bgroups);
		ret["allowedCategories"] = Bson(bcats);

		return Bson(ret);
	}
}
