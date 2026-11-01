# Turn campaign ideas into pages

Use this workflow to turn a document or a few rough ideas into linked notes for
the pirate campaign. The assistant proposes drafts; you decide what becomes a
campaign page.

## 1. Choose a small piece

On your phone or computer, open [Campaign assistant](https://campaign-ai.hub.frey)
while connected to Frey. Sign in and start a new chat. Attach one Markdown
document or paste a short section. The assistant has a limited context window,
so split long documents into smaller sections and check that it has read the
whole section you sent.

The assistant is being set up. Its link may show an error until the model has
finished downloading. File selection and answers still need to be tested on
your phone.

## 2. Find the pages

Paste this prompt with your document:

```text
I am preparing a pirate tabletop campaign. Organize the attached ideas into a
small set of useful SilverBullet pages. Start with a list of suggested page
titles, the kind of page (place, person, faction, species, ship, event or
other), and a one-sentence description for each. Show possible links between
them and list questions or contradictions in my source.

Preserve my wording and meaning. Treat these notes as ideas, not established
campaign facts. Do not invent names or details. If something is unclear, say
so. If you suggest something new, label it clearly as a suggestion. Use only
the material I supplied in this chat.
```

Check the list. Tell the assistant which pages to combine, rename or leave out.
For a large document, repeat with the next section. Keep your original file as
the source; the assistant does not automatically store it in SilverBullet.

## 3. Draft one page at a time

Ask for a specific page using this prompt, replacing the bracketed parts:

```text
Draft the SilverBullet page [page title] from my supplied notes. Output only
the Markdown for that page, with a title, a short overview, useful details,
related pages as [[wiki links]], and open questions. Mark it as a campaign idea
that needs GM review. Include the source document name [document name] and
section if available.

Do not add facts that are absent from my source. Clearly label any optional
suggestion. Do not assume a relationship or a page exists unless my notes or I
say so. If the notes conflict or do not answer something, say so.
```

The model can still misunderstand or invent details despite the instructions.
Compare each draft and link to your original, then correct it before saving.

## 4. Save the reviewed page

In SilverBullet, start from [[Campaigns/Pirate/Creating Campaign Pages|Create a campaign page]]
or open an existing page you want to update. Paste the reviewed Markdown. Use
the same page names in links and page titles; create missing pages only when
you want them. Add a link from [[Campaigns/Pirate/People and Places|People, places and factions]]
or [[Campaigns/Pirate/Story and Sessions|Story and sessions]] when useful.

Keep established events, future plans, rumors and AI suggestions clearly
separate. The current Notes space is shared with Frey's `notes` group; it is
not yet a private GM-only space. Do not put GM secrets or private player
information there until a separate access boundary is ready.

The assistant sees only what you put in the chat. It cannot look up your
existing notes or save pages for you. Conversations may remain in the browser
on the device you used, so protect the device and clear site data if needed.
