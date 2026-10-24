// Tests of the JSON reader and writer (portable C++).
//
//   clang++ -std=c++11 -I.. minijson_test.cpp ../MiniJson.cpp -o /tmp/minijson_test && /tmp/minijson_test
#include "MiniJson.h"
#include <cstdio>

using namespace vjson;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main() {
    Value v;
    CHECK(parse("{\"a\": 1, \"b\": [true, null, \"x\"], \"c\": {\"d\": -2.5e1}}", v));
    CHECK(v.isObject() && v["a"].asNumber() == 1);
    CHECK(v["b"].items().size() == 3 && v["b"].items()[0].asBool() && v["b"].items()[1].isNull() && v["b"].items()[2].asString() == "x");
    CHECK(v["c"]["d"].asNumber() == -25);
    CHECK(v["missing"].isNull() && v["missing"]["deeper"].isNull());

    // escapes, a surrogate pair (U+1F600), accents kept as UTF-8
    CHECK(parse("\"line\\nbreak \\u00e9 \\ud83d\\ude00 \\\"q\\\" \\/\"", v));
    CHECK(v.asString() == "line\nbreak \xC3\xA9 \xF0\x9F\x98\x80 \"q\" /");

    // a byte order mark, then spaces
    CHECK(parse("\xEF\xBB\xBF  [1, 2 ]  ", v) && v.items().size() == 2);

    // what is not JSON
    CHECK(!parse("", v));
    CHECK(!parse("{", v));
    CHECK(!parse("{\"a\": }", v));
    CHECK(!parse("[1,]", v));
    CHECK(!parse("\"raw\nbreak\"", v));
    CHECK(!parse("\"\\ud83d\"", v));          // half a pair
    CHECK(!parse("[1] x", v));
    CHECK(!parse("{\"a\":1,}", v));
    CHECK(!parse("[1-2]", v) && !parse("[1e+]", v) && !parse("[01]", v) && !parse("[1.]", v) && !parse("[.5]", v) && !parse("[-]", v) && !parse("[+1]", v));
    CHECK(parse("[0, -0.5, 1E3, 2e-2, 10]", v) && v.items().size() == 5 && v.items()[2].asNumber() == 1000);
    CHECK(v.isNull() == false);
    CHECK(!parse("{", v));
    CHECK(v.isNull());                       // a failed parse leaves nothing behind
    std::string deep(200, '[');
    CHECK(!parse(deep, v));                  // too deep, and no crash

    // writing and reading it again
    Value o = Value::object();
    o.set("title", Value::string("T\xC3\xB3m t\xE1\xBA\xAFt \"x\"\n\t/"));
    o.set("count", Value::number(3));
    o.set("ratio", Value::number(0.5));
    o.set("ok", Value::boolean(true));
    Value list = Value::array();
    list.push(Value::string("a"));
    list.push(Value());
    o.set("list", list);
    o.set("empty", Value::array());
    std::string text = write(o);
    Value back;
    CHECK(parse(text, back));
    CHECK(back["title"].asString() == o["title"].asString());
    CHECK(back["count"].asNumber() == 3 && back["ratio"].asNumber() == 0.5 && back["ok"].asBool());
    CHECK(back["list"].items().size() == 2 && back["empty"].items().empty());
    CHECK(text.find("\"count\": 3\n") != std::string::npos || text.find("\"count\": 3,") != std::string::npos); // an integer has no ".0"
    CHECK(text.find("\xC3\xB3") != std::string::npos);                                                  // not turned into \u00f3
    CHECK(text.find("\\/") == std::string::npos);                                                       // "/" is not escaped
    CHECK(write(o, false).find('\n') == std::string::npos);                                             // compact has no line breaks

    // keys keep their order, a repeated key is the last value
    CHECK(parse("{\"z\":1,\"a\":2,\"z\":3}", v));
    CHECK(v.members().size() == 2 && v.members()[0].first == "z" && v["z"].asNumber() == 3);

    if (failures == 0)
        printf("minijson_test: all passed\n");
    return failures == 0 ? 0 : 1;
}
