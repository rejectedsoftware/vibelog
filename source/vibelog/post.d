module vibelog.post;

import vibe.data.bson;
import vibe.textfilter.markdown;
import vibe.textfilter.html;

import std.array;
import std.conv;
public import std.datetime;


class Post {
	BsonObjectID id;
	bool isPublic;
	bool commentsAllowed;
	string slug; // url entity to identify this post - generated from the header by default
	string author;  // user name
	string category; // can be hierarchical using dotted.syntax.format
	SysTime date;
	string header;
	string subHeader;
	string content;
	string headerImage;
	string[] tags;
	string[] trackbacks;

	this()
	{
		id  = BsonObjectID.generate();
		date = Clock.currTime().toUTC();
	}

	@property string name() const { return slug.length ? slug : id.toString(); }
	
	static Post fromBson(Bson bson)
	{
		auto ret = new Post;
		ret.id = cast(BsonObjectID)bson["_id"];
		ret.isPublic = cast(bool)bson["isPublic"];
		ret.commentsAllowed = cast(bool)bson["commentsAllowed"];
		ret.slug = cast(string)bson["slug"];
		ret.author = cast(string)bson["author"];
		ret.category = cast(string)bson["category"];
		ret.date = SysTime.fromISOExtString(cast(string)bson["date"]);
		ret.header = cast(string)bson["header"];
		ret.subHeader = cast(string)bson["subHeader"];
		ret.headerImage = cast(string)bson["headerImage"];
		ret.content = cast(string)bson["content"];
		foreach( t; cast(Bson[])bson["tags"] )
			ret.tags ~= cast(string)t;
		return ret;
	}
	
	Bson toBson()
	const {
		Bson[] btags;
		foreach( t; tags )
			btags ~= Bson(t);

		Bson[string] ret;
		ret["_id"] = Bson(id);
		ret["isPublic"] = Bson(isPublic);
		ret["commentsAllowed"] = Bson(commentsAllowed);
		ret["slug"] = Bson(slug);
		ret["author"] = Bson(author);
		ret["category"] = Bson(category);
		ret["date"] = Bson(date.toISOExtString());
		ret["header"] = Bson(header);
		ret["subHeader"] = Bson(subHeader);
		ret["headerImage"] = Bson(headerImage);
		ret["content"] = Bson(content);
		ret["tags"] = Bson(btags);

		return Bson(ret);
	}

	string renderSubHeaderAsHtml()
	const {
		auto ret = appender!string();
		filterMarkdown(ret, subHeader);
		return ret.data;
	}

	string renderContentAsHtml(string function(string)[] filters)
	const {
		auto html = filterMarkdown(content);
		foreach( flt; filters )
			html = flt(html);
		return html;
	}
}

class Comment {
	BsonObjectID id;
	BsonObjectID postId;
	bool isPublic;
	SysTime date;
	int answerTo;
	string authorName;
	string authorMail;
	string authorHomepage;
	string authorIP;
	string header;
	string content;

	static Comment fromBson(Bson bson)
	{
		auto ret = new Comment;
		ret.id = cast(BsonObjectID)bson["_id"];
		ret.postId = cast(BsonObjectID)bson["postId"];
		ret.isPublic = cast(bool)bson["isPublic"];
		ret.date = SysTime.fromISOExtString(cast(string)bson["date"]);
		ret.answerTo = cast(int)bson["answerTo"];
		ret.authorName = cast(string)bson["authorName"];
		ret.authorMail = cast(string)bson["authorMail"];
		ret.authorHomepage = cast(string)bson["authorHomepage"];
		ret.authorIP = bson["authorIP"].opt!string();
		ret.header = cast(string)bson["header"];
		ret.content = cast(string)bson["content"];
		return ret;
	}
	
	Bson toBson()
	const {
		Bson[string] ret;
		ret["_id"] = Bson(id);
		ret["postId"] = Bson(postId);
		ret["isPublic"] = Bson(isPublic);
		ret["date"] = Bson(date.toISOExtString());
		ret["answerTo"] = Bson(answerTo);
		ret["authorName"] = Bson(authorName);
		ret["authorMail"] = Bson(authorMail);
		ret["authorHomepage"] = Bson(authorHomepage);
		ret["authorIP"] = Bson(authorIP);
		ret["header"] = Bson(header);
		ret["content"] = Bson(content);
		return Bson(ret);
	}

	string renderContentAsHtml()
	const {
		auto ret = appender!string();
		filterMarkdown(ret, htmlEscape(content));
		return ret.data;
	}
}

string makeSlugFromHeader(string header)
{
	Appender!string ret;
	foreach( dchar ch; header ){
		switch( ch ){
			default:
				ret.put('-');
				break;
			case '"', '\'', '´', '`', '.', ',', ';', '!', '?':
				break;
			case 'A': .. case 'Z'+1:
				ret.put(cast(dchar)(ch - 'A' + 'a'));
				break;
			case 'a': .. case 'z'+1:
			case '0': .. case '9'+1:
				ret.put(ch);
				break;
		}
	}
	return ret.data;
}
