//! MCP (Model Context Protocol) tool integration via [`bote`].
//!
//! Exposes vidya's search, lookup, compare, and list operations as MCP tools
//! that AI agents can invoke through JSON-RPC.
//!
//! # Tools
//!
//! - `search_concepts` — Search the registry by text, tags, and language
//! - `get_concept` — Look up a specific concept by ID
//! - `compare_languages` — Compare a concept across languages
//! - `list_concepts` — List all concepts, optionally filtered by topic
//!
//! # Example
//!
//! ```rust,no_run
//! use vidya::mcp::build_dispatcher;
//! use vidya::loader::load_all;
//! use std::path::Path;
//!
//! let registry = load_all(Path::new("content")).unwrap();
//! let dispatcher = build_dispatcher(registry);
//! ```

use crate::Language;
use crate::compare::compare;
use crate::registry::Registry;
use crate::search::{SearchQuery, search};
use bote::dispatch::Dispatcher;
use bote::registry::ToolRegistry;
use bote::registry::ToolSchema;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::sync::Arc;

/// Build a [`Dispatcher`] with all vidya MCP tools registered.
///
/// The returned dispatcher is ready to handle JSON-RPC requests.
/// The registry is shared via `Arc` across all tool handlers.
pub fn build_dispatcher(registry: Registry) -> Dispatcher {
    let mut tool_registry = ToolRegistry::new();
    let reg = Arc::new(registry);

    // ── search_concepts ────────────────────────────────────────────
    let search_schema = ToolSchema::new(
        "object",
        HashMap::from([
            (
                "query".into(),
                json!({"type": "string", "description": "Free-text search query"}),
            ),
            (
                "language".into(),
                json!({"type": "string", "description": "Filter by language (e.g. 'rust', 'python')"}),
            ),
            (
                "tags".into(),
                json!({"type": "array", "items": {"type": "string"}, "description": "Required tags (all must match)"}),
            ),
            (
                "limit".into(),
                json!({"type": "integer", "description": "Maximum results to return"}),
            ),
        ]),
        vec!["query".into()],
    );
    let search_tool = bote::registry::ToolDef::new(
        "search_concepts",
        "Search the programming reference by text, tags, and language",
        search_schema,
    );
    tool_registry.register(search_tool);

    // ── get_concept ────────────────────────────────────────────────
    let get_schema = ToolSchema::new(
        "object",
        HashMap::from([(
            "id".into(),
            json!({"type": "string", "description": "Concept ID (e.g. 'strings', 'error_handling')"}),
        )]),
        vec!["id".into()],
    );
    let get_tool = bote::registry::ToolDef::new(
        "get_concept",
        "Get a specific programming concept by ID with all details",
        get_schema,
    );
    tool_registry.register(get_tool);

    // ── compare_languages ──────────────────────────────────────────
    let compare_schema = ToolSchema::new(
        "object",
        HashMap::from([
            (
                "concept_id".into(),
                json!({"type": "string", "description": "Concept ID to compare"}),
            ),
            (
                "languages".into(),
                json!({"type": "array", "items": {"type": "string"}, "description": "Languages to compare (e.g. ['rust', 'python'])"}),
            ),
        ]),
        vec!["concept_id".into(), "languages".into()],
    );
    let compare_tool = bote::registry::ToolDef::new(
        "compare_languages",
        "Compare a concept's implementation across programming languages",
        compare_schema,
    );
    tool_registry.register(compare_tool);

    // ── list_concepts ──────────────────────────────────────────────
    let list_schema = ToolSchema::new(
        "object",
        HashMap::from([(
            "topic".into(),
            json!({"type": "string", "description": "Filter by topic (e.g. 'DataTypes', 'Concurrency')"}),
        )]),
        vec![],
    );
    let list_tool = bote::registry::ToolDef::new(
        "list_concepts",
        "List all programming concepts, optionally filtered by topic",
        list_schema,
    );
    tool_registry.register(list_tool);

    // ── Build dispatcher with handlers ─────────────────────────────
    let mut dispatcher = Dispatcher::new(tool_registry);

    // search_concepts handler
    let reg_clone = Arc::clone(&reg);
    dispatcher.handle(
        "search_concepts",
        Arc::new(move |params: Value| -> Value {
            let query_text = params.get("query").and_then(|v| v.as_str()).unwrap_or("");

            let mut sq = SearchQuery::text(query_text);

            if let Some(lang_str) = params.get("language").and_then(|v| v.as_str())
                && let Some(lang) = Language::from_str_loose(lang_str)
            {
                sq.language = Some(lang);
            }

            if let Some(tags) = params.get("tags").and_then(|v| v.as_array()) {
                sq.tags = tags
                    .iter()
                    .filter_map(|t| t.as_str().map(String::from))
                    .collect();
            }

            if let Some(limit) = params.get("limit").and_then(|v| v.as_u64()) {
                sq.limit = Some(limit as usize);
            }

            let results = search(&reg_clone, &sq);
            json!(results)
        }),
    );

    // get_concept handler
    let reg_clone = Arc::clone(&reg);
    dispatcher.handle(
        "get_concept",
        Arc::new(move |params: Value| -> Value {
            let id = params.get("id").and_then(|v| v.as_str()).unwrap_or("");

            match reg_clone.get(id) {
                Some(concept) => json!(concept),
                None => json!({"error": format!("concept not found: {id}")}),
            }
        }),
    );

    // compare_languages handler
    let reg_clone = Arc::clone(&reg);
    dispatcher.handle(
        "compare_languages",
        Arc::new(move |params: Value| -> Value {
            let concept_id = params
                .get("concept_id")
                .and_then(|v| v.as_str())
                .unwrap_or("");

            let languages: Vec<Language> = params
                .get("languages")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().and_then(Language::from_str_loose))
                        .collect()
                })
                .unwrap_or_default();

            match compare(&reg_clone, concept_id, &languages) {
                Ok(comparison) => json!(comparison),
                Err(e) => json!({"error": e.to_string()}),
            }
        }),
    );

    // list_concepts handler
    let reg_clone = Arc::clone(&reg);
    dispatcher.handle(
        "list_concepts",
        Arc::new(move |params: Value| -> Value {
            let topic_str = params.get("topic").and_then(|v| v.as_str());

            let concepts: Vec<Value> = if let Some(topic_name) = topic_str {
                // Try to parse topic — do a case-insensitive match
                let topic_lower = topic_name.to_lowercase();
                reg_clone
                    .list()
                    .into_iter()
                    .filter(|c| c.topic.to_string().to_lowercase() == topic_lower)
                    .map(|c| {
                        json!({
                            "id": c.id,
                            "title": c.title,
                            "topic": c.topic.to_string(),
                            "languages": c.available_languages().iter().map(|l| l.display_name()).collect::<Vec<_>>(),
                        })
                    })
                    .collect()
            } else {
                reg_clone
                    .list()
                    .into_iter()
                    .map(|c| {
                        json!({
                            "id": c.id,
                            "title": c.title,
                            "topic": c.topic.to_string(),
                            "languages": c.available_languages().iter().map(|l| l.display_name()).collect::<Vec<_>>(),
                        })
                    })
                    .collect()
            };

            json!({"concepts": concepts, "count": concepts.len()})
        }),
    );

    dispatcher
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Registry;
    use crate::concept::{Concept, Example, Topic};

    fn test_registry() -> Registry {
        let mut reg = Registry::new();
        let mut examples = HashMap::new();
        examples.insert(
            Language::Rust,
            Example {
                language: Language::Rust,
                code: "let s = String::new();".into(),
                explanation: "Rust strings".into(),
                source_path: None,
            },
        );
        reg.register(Concept {
            id: "strings".into(),
            title: "String Handling".into(),
            topic: Topic::DataTypes,
            description: "Working with text.".into(),
            best_practices: vec![],
            gotchas: vec![],
            performance_notes: vec![],
            tags: vec!["text".into()],
            examples,
        });
        reg
    }

    fn call_tool(tool_name: &str, arguments: Value) -> bote::protocol::JsonRpcRequest {
        bote::protocol::JsonRpcRequest::new(1, "tools/call")
            .with_params(json!({"name": tool_name, "arguments": arguments}))
    }

    #[test]
    fn dispatcher_search() {
        let dispatcher = build_dispatcher(test_registry());
        let request = call_tool("search_concepts", json!({"query": "string"}));
        let response = dispatcher.dispatch(&request).unwrap();
        let results = response.result.unwrap();
        let arr = results.as_array().unwrap();
        assert_eq!(arr.len(), 1);
        assert_eq!(arr[0]["id"], "strings");
    }

    #[test]
    fn dispatcher_get_concept() {
        let dispatcher = build_dispatcher(test_registry());
        let request = call_tool("get_concept", json!({"id": "strings"}));
        let response = dispatcher.dispatch(&request).unwrap();
        let concept = response.result.unwrap();
        assert_eq!(concept["id"], "strings");
        assert_eq!(concept["title"], "String Handling");
    }

    #[test]
    fn dispatcher_get_concept_not_found() {
        let dispatcher = build_dispatcher(test_registry());
        let request = call_tool("get_concept", json!({"id": "missing"}));
        let response = dispatcher.dispatch(&request).unwrap();
        let result = response.result.unwrap();
        assert!(result["error"].as_str().unwrap().contains("not found"));
    }

    #[test]
    fn dispatcher_list_concepts() {
        let dispatcher = build_dispatcher(test_registry());
        let request = call_tool("list_concepts", json!({}));
        let response = dispatcher.dispatch(&request).unwrap();
        let result = response.result.unwrap();
        assert_eq!(result["count"], 1);
    }

    #[test]
    fn dispatcher_compare() {
        let dispatcher = build_dispatcher(test_registry());
        let request = call_tool(
            "compare_languages",
            json!({"concept_id": "strings", "languages": ["rust"]}),
        );
        let response = dispatcher.dispatch(&request).unwrap();
        let result = response.result.unwrap();
        assert_eq!(result["concept_id"], "strings");
    }
}
