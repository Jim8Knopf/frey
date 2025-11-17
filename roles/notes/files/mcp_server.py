#!/usr/bin/env python3
"""
SiYuan MCP Server
Model Context Protocol server for SiYuan note-taking integration

Provides tools for voice assistants and LLMs to interact with SiYuan notes:
- create_note: Create a new note
- search_notes: Search existing notes
- append_to_note: Add content to existing note
- list_notebooks: List all notebooks
- get_note: Retrieve note content

Environment Variables:
- SIYUAN_API_URL: SiYuan API endpoint (default: http://siyuan:6806)
- MCP_PORT: Port to listen on (default: 6808)
"""

import asyncio
import json
import os
from datetime import datetime
from typing import Any

import httpx
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

# Configuration
SIYUAN_API_URL = os.getenv("SIYUAN_API_URL", "http://siyuan:6806")
MCP_PORT = int(os.getenv("MCP_PORT", "6808"))

# Initialize MCP server
app = Server("siyuan-notes")


class SiYuanClient:
    """Client for SiYuan API"""

    def __init__(self, base_url: str):
        self.base_url = base_url
        self.client = httpx.AsyncClient(timeout=30.0)

    async def request(self, endpoint: str, data: dict = None) -> dict:
        """Make request to SiYuan API"""
        url = f"{self.base_url}/api/{endpoint}"
        response = await self.client.post(url, json=data or {})
        response.raise_for_status()
        result = response.json()

        if result.get("code") != 0:
            raise Exception(f"SiYuan API error: {result.get('msg', 'Unknown error')}")

        return result.get("data", {})

    async def list_notebooks(self) -> list[dict]:
        """List all notebooks"""
        return await self.request("notebook/lsNotebooks")

    async def create_note(self, notebook_id: str, path: str, markdown: str) -> dict:
        """Create a new note"""
        data = {
            "notebook": notebook_id,
            "path": path,
            "markdown": markdown
        }
        return await self.request("filetree/createDocWithMd", data)

    async def search_notes(self, query: str, method: int = 0) -> list[dict]:
        """Search notes (method: 0=keyword, 1=regex, 2=sql)"""
        data = {
            "query": query,
            "method": method
        }
        return await self.request("search/fullTextSearchBlock", data)

    async def get_block(self, block_id: str) -> dict:
        """Get block content by ID"""
        data = {"id": block_id}
        return await self.request("block/getBlockKramdown", data)

    async def append_block(self, parent_id: str, markdown: str) -> dict:
        """Append content to a note"""
        data = {
            "parentID": parent_id,
            "dataType": "markdown",
            "data": markdown
        }
        return await self.request("block/appendBlock", data)


# Initialize SiYuan client
siyuan = SiYuanClient(SIYUAN_API_URL)


@app.list_tools()
async def list_tools() -> list[Tool]:
    """List available MCP tools"""
    return [
        Tool(
            name="create_note",
            description="Create a new note in SiYuan. Perfect for capturing ideas, meeting notes, or quick thoughts.",
            inputSchema={
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Note title"
                    },
                    "content": {
                        "type": "string",
                        "description": "Note content in markdown format"
                    },
                    "notebook": {
                        "type": "string",
                        "description": "Notebook ID (optional, uses first notebook if not specified)"
                    },
                    "path": {
                        "type": "string",
                        "description": "Path within notebook (optional, defaults to root with timestamp)"
                    }
                },
                "required": ["title", "content"]
            }
        ),
        Tool(
            name="search_notes",
            description="Search existing notes by keyword. Returns matching notes with context.",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query (keywords or phrases)"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of results (default: 10)"
                    }
                },
                "required": ["query"]
            }
        ),
        Tool(
            name="append_to_note",
            description="Append content to an existing note. Great for adding updates or new information.",
            inputSchema={
                "type": "object",
                "properties": {
                    "note_id": {
                        "type": "string",
                        "description": "Note block ID to append to"
                    },
                    "content": {
                        "type": "string",
                        "description": "Content to append in markdown format"
                    }
                },
                "required": ["note_id", "content"]
            }
        ),
        Tool(
            name="list_notebooks",
            description="List all available notebooks in SiYuan.",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        ),
        Tool(
            name="get_note",
            description="Retrieve the full content of a specific note by ID.",
            inputSchema={
                "type": "object",
                "properties": {
                    "note_id": {
                        "type": "string",
                        "description": "Note block ID to retrieve"
                    }
                },
                "required": ["note_id"]
            }
        )
    ]


@app.call_tool()
async def call_tool(name: str, arguments: Any) -> list[TextContent]:
    """Handle tool calls"""

    try:
        if name == "create_note":
            # Get notebook ID
            notebook_id = arguments.get("notebook")
            if not notebook_id:
                notebooks = await siyuan.list_notebooks()
                if not notebooks:
                    return [TextContent(type="text", text="Error: No notebooks found")]
                notebook_id = notebooks[0]["id"]

            # Generate path with timestamp if not provided
            path = arguments.get("path")
            if not path:
                timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
                safe_title = "".join(c if c.isalnum() or c in (' ', '-', '_') else '_'
                                    for c in arguments["title"])
                path = f"/{timestamp}-{safe_title}"

            # Create markdown content with title
            markdown = f"# {arguments['title']}\n\n{arguments['content']}"

            # Create the note
            result = await siyuan.create_note(notebook_id, path, markdown)

            return [TextContent(
                type="text",
                text=f"✅ Note created successfully!\n\nTitle: {arguments['title']}\nID: {result.get('id', 'N/A')}\nPath: {path}"
            )]

        elif name == "search_notes":
            query = arguments["query"]
            limit = arguments.get("limit", 10)

            results = await siyuan.search_notes(query)

            if not results:
                return [TextContent(type="text", text=f"No notes found matching '{query}'")]

            # Format results
            output = f"Found {len(results[:limit])} note(s) matching '{query}':\n\n"

            for i, block in enumerate(results[:limit], 1):
                content = block.get("content", "")
                # Truncate long content
                if len(content) > 200:
                    content = content[:200] + "..."

                output += f"{i}. **{block.get('hPath', 'Untitled')}**\n"
                output += f"   ID: `{block.get('id', 'N/A')}`\n"
                output += f"   {content}\n\n"

            return [TextContent(type="text", text=output)]

        elif name == "append_to_note":
            note_id = arguments["note_id"]
            content = arguments["content"]

            # Append content
            result = await siyuan.append_block(note_id, content)

            return [TextContent(
                type="text",
                text=f"✅ Content appended successfully to note {note_id}"
            )]

        elif name == "list_notebooks":
            notebooks = await siyuan.list_notebooks()

            if not notebooks:
                return [TextContent(type="text", text="No notebooks found")]

            output = f"Found {len(notebooks)} notebook(s):\n\n"
            for nb in notebooks:
                output += f"- **{nb.get('name', 'Untitled')}**\n"
                output += f"  ID: `{nb.get('id', 'N/A')}`\n"
                output += f"  Icon: {nb.get('icon', '📓')}\n\n"

            return [TextContent(type="text", text=output)]

        elif name == "get_note":
            note_id = arguments["note_id"]

            result = await siyuan.get_block(note_id)

            content = result.get("kramdown", "No content found")

            return [TextContent(
                type="text",
                text=f"Note ID: {note_id}\n\n{content}"
            )]

        else:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]

    except Exception as e:
        return [TextContent(type="text", text=f"Error: {str(e)}")]


async def main():
    """Run MCP server"""
    async with stdio_server() as (read_stream, write_stream):
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options()
        )


if __name__ == "__main__":
    asyncio.run(main())
