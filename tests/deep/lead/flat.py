import sys,re,json
raw=open(sys.argv[1]).read()
m=re.search(r'\{"verdict.*',raw,re.S)
x=json.JSONDecoder().raw_decode(m.group(0))[0]['data']['xml']
# print top-level-ish blocks: paragraphs, rows with text
x=re.sub(r"<text id='[^']*'>",'',x); x=x.replace('</text>','')
x=re.sub(r"<bold>|</bold>",'**',x); x=re.sub(r"<code>|</code>",'`',x)
x=re.sub(r"<cell [^>]*>",' | ',x)
x=re.sub(r"<row id='([^']*)'[^>]*>",r"\n  ROW \1: ",x)
x=re.sub(r"<paragraph id='([^']*)'[^>]*heading='(\d)'[^>]*>",r"\n[\1 H\2] ",x)
x=re.sub(r"<(table|list|listItem|codeBlock|code_block|pending) id='([^']*)'[^>]*>",r"\n<\1 \2>",x)
x=re.sub(r"<paragraph id='([^']*)'[^>]*>",r" {\1} ",x)
x=re.sub(r"</?[a-zA-Z][^>]*>",'',x)
print(x)
