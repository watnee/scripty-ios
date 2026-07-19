//
//  ScriptModel+TitlePage.swift
//  scripty
//
//  Title-page and script-import affordances hanging off an open script.
//  Both are link-gated: the server decides whether this reader may edit the
//  front matter or replace the screenplay.
//

import Foundation

extension ScriptModel {
    /// The project advertises `update` only when the front matter is editable;
    /// the title page is still readable without it.
    var canEditTitlePage: Bool { project.hasLink(.update) }

    /// `importScript` is advertised only when this reader may replace the
    /// whole screenplay.
    var canImportScript: Bool { project.hasLink(.importScript) }

    func makeTitlePageModel() -> TitlePageModel {
        TitlePageModel(app: app, project: project)
    }

    func makeScriptImportModel() -> ScriptImportModel {
        ScriptImportModel(app: app, project: project)
    }
}
