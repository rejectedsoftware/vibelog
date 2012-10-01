module vibelog.rss;

import vibe.stream.stream;
import vibe.inet.message : toRFC822DateTimeString;

import std.datetime;


class RssFeed {
	RssChannel[] channels;

	void render(OutputStream dst)
	{
		dst.write("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n", false);
		dst.write("<rss version=\"2.0\">\n", false);
		foreach( ch; channels )
			ch.render(dst);
		dst.write("</rss>\n", false);
	}
}

class RssChannel {
	string title;
	string link;
	string description;
	string language = "en-us";
	string copyright;
	SysTime pubDate;

	string imageTitle;
	string imageUrl;
	string imageLink;

	RssEntry[] entries;

	void render(OutputStream dst)
	{
		dst.write("\t<channel>\n", false);
		dst.write("\t\t<title>", false); dst.write(title, false); dst.write("</title>\n", false);
		dst.write("\t\t<link>", false); dst.write(link, false); dst.write("</link>\n", false);
		dst.write("\t\t<description>", false); dst.write(description, false); dst.write("</description>\n", false);
		dst.write("\t\t<language>", false); dst.write(language, false); dst.write("</language>\n", false);
		dst.write("\t\t<copyright>", false); dst.write(copyright, false); dst.write("</copyright>\n", false);
		dst.write("\t\t<pubDate>", false); dst.write(toRFC822DateTimeString(pubDate), false); dst.write("</pubDate>\n", false);
		if( imageUrl.length ){
			dst.write("\t\t<image>\n", false);
			dst.write("\t\t\t<url>", false); dst.write(imageUrl, false); dst.write("</url>\n", false);
			dst.write("\t\t\t<title>", false); dst.write(imageTitle, false); dst.write("</title>\n", false);
			dst.write("\t\t\t<link>", false); dst.write(imageLink, false); dst.write("</link>\n", false);
			dst.write("\t\t</image>\n", false);
		}
		foreach( e; entries )
			e.render(dst);
		dst.write("\t</channel>\n", false);
	}
}

class RssEntry {
	string title;
	string description;
	string link;
	string language = "en-us";
	string author;
	string guid;
	SysTime pubDate;

	void render(OutputStream dst)
	{
		dst.write("\t\t<item>\n", false);
		dst.write("\t\t\t<title>", false); dst.write(title, false); dst.write("</title>\n", false);
		dst.write("\t\t\t<description>", false); dst.write(description, false); dst.write("</description>\n", false);
		dst.write("\t\t\t<link>", false); dst.write(link, false); dst.write("</link>\n", false);
		dst.write("\t\t\t<author>", false); dst.write(author, false); dst.write("</author>\n", false);
		dst.write("\t\t\t<guid>", false); dst.write(guid, false); dst.write("</guid>\n", false);
		dst.write("\t\t\t<pubDate>", false); dst.write(toRFC822DateTimeString(pubDate), false); dst.write("</pubDate>\n", false);
		dst.write("\t\t</item>\n", false);
	}
}
