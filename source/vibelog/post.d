module vibelog.post;

import vibelog.settings;

import vibe.data.bson;
import vibe.textfilter.markdown;
import vibe.textfilter.html;

import std.array;
import std.conv;
import std.string : strip;
public import std.datetime;

import stringex.unidecode;


final class Post {
	BsonObjectID id;
	bool isPublic;
	bool commentsAllowed;
	string slug; // url entity to identify this post - generated from the header by default
	string author;  // user name
	string category; // can be hierarchical using dotted.syntax.format
	SysTime date;
	string header;
	string headerImage;
	string subHeader;
	string content;
	string[] filters;
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
		ret.headerImage = cast(string)bson["headerImage"];
		ret.header = cast(string)bson["header"];
		ret.subHeader = cast(string)bson["subHeader"];
		ret.content = cast(string)bson["content"];

		if (bson["filters"].isNull) ret.filters = ["markdown"];
		else {
			foreach (f; cast(Bson[])bson["filters"])
				ret.filters ~= cast(string)f;
		}

		if (!bson["tags"].isNull)
			foreach (t; cast(Bson[])bson["tags"])
				ret.tags ~= cast(string)t;

		return ret;
	}

	Bson toBson()
	const {

		Bson[string] ret;
		ret["_id"] = Bson(id);
		ret["isPublic"] = Bson(isPublic);
		ret["commentsAllowed"] = Bson(commentsAllowed);
		ret["slug"] = Bson(slug);
		ret["author"] = Bson(author);
		ret["category"] = Bson(category);
		ret["date"] = Bson(date.toISOExtString());
		ret["headerImage"] = Bson(headerImage);
		ret["header"] = Bson(header);
		ret["subHeader"] = Bson(subHeader);
		ret["content"] = Bson(content);

		import std.algorithm : map;
		import std.array : array;
		ret["filters"] = Bson(filters.map!Bson.array);
		ret["tags"] = Bson(tags.map!Bson.array);

		return Bson(ret);
	}

	string renderSubHeaderAsHtml(VibeLogSettings settings)
	const {
		import std.algorithm : canFind;
		if (filters.canFind("markdown"))
		{
			auto ret = appender!string();
			filterMarkdown(ret, subHeader, settings.markdownSettings);
			return ret.data;
		}
		else
		{
			return subHeader;
		}
	}

	string renderContentAsHtml(VibeLogSettings settings, string page_path = "", int header_level_nesting = 0)
	const {

		import std.algorithm : canFind;
		string html = content;
		if (filters.canFind("markdown"))
		{
			scope ms = new MarkdownSettings;
			ms.flags = settings.markdownSettings.flags;
			ms.headingBaseLevel = settings.markdownSettings.headingBaseLevel + header_level_nesting;
			if (page_path != "")
			{
				ms.urlFilter = (lnk, is_image) {
					import std.algorithm : startsWith;
					if (lnk.startsWith("http://") || lnk.startsWith("https://"))
						return lnk;
					auto pp = Path(page_path);
					if (!pp.endsWithSlash)
						pp = pp[0 .. $-1];
					return (settings.siteURL.path~("posts/"~slug~"/"~lnk)).relativeTo(pp).toString();
				};
			}
			html = filterMarkdown(html, ms);
		}
		foreach (flt; settings.textFilters)
			html = flt(html);
		return html;
	}
}

final class Comment {
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
		// filter with GitHub-like features, but without unsafe inline-HTML
		filterMarkdown(ret, content, MarkdownFlags.forumDefault);
		return ret.data;
	}
}

UniDecoder unidecoder;

string makeSlugFromHeader(string header)
{
	Appender!string ret;
	auto decoded_header = getDecoder().decode(header);
	foreach( dchar ch; strip(decoded_header) ){
		switch( ch ){
			default:
				ret.put('-');
				break;
			case '"', '\'', '´', '`', '.', ',', ';', '!', '?', '¿', '¡':
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

unittest {
	assert(makeSlugFromHeader("sample title") == "sample-title");
	assert(makeSlugFromHeader("Sample Title") == "sample-title");
	assert(makeSlugFromHeader("  Sample Title2  ") == "sample-title2");
	assert(makeSlugFromHeader("反清復明") == "fan-qing-fu-ming");
	assert(makeSlugFromHeader("φύλλο") == "phullo");
	assert(makeSlugFromHeader("ខេមរភាសា") == "khemrbhaasaa");
	assert(makeSlugFromHeader("zweitgrößte der Europäischen Union") == "zweitgrosste-der-europaischen-union");
	assert(makeSlugFromHeader("østlige og vestlige del udviklede sig uafhængigt ") == "ostlige-og-vestlige-del-udviklede-sig-uafhaengigt");
	assert(makeSlugFromHeader("¿pchnąć w tę łódź jeża lub ośm skrzyń fig?") == "pchnac-w-te-lodz-jeza-lub-osm-skrzyn-fig");
	assert(makeSlugFromHeader("¼ €") == "1-4-eu");
}

private UniDecoder getDecoder() {
	if (unidecoder is null) {
		unidecoder = new UniDecoder();
	}
	return unidecoder;
}
