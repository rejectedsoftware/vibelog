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
	string header; // Title/heading
	string headerImage; // URL of large header image
	string summaryTitle; // Short title used for the summary (<=70chars)
	string summary; // Short summary of the article (<=240 chars), displayed on cards
	string subHeader; // First paragraph of the articule, displayed on overview pages
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
		ret.summary = bson["summary"].opt!string;
		ret.summaryTitle = bson["summaryTitle"].opt!string;

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
		ret["summary"] = Bson(summary);
		ret["summaryTitle"] = Bson(summaryTitle);

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
					if (lnk.startsWith("#")) return lnk;
					auto pp = InetPath(page_path);
					if (!pp.endsWithSlash)
						pp = pp.parentPath;
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

string makeSlugFromHeader(string header)
{
	Appender!string ret;
	auto decoded_header = unidecode(header).replace("[?]", "-");
	foreach (dchar ch; strip(decoded_header)) {
		switch (ch) {
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
