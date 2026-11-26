package com.ar.dosarcusina.store.examples

import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Asset

/**
 * An example section and everything filed under it, as the iOS app's `ExampleDataService`
 * (`holdsSomethingReal`, `makeReal`, `tree(of:)`): what removing the examples asks of one, and what
 * keeping one as the person's does to it.
 */
internal object ExampleTree {
    /** [asset] and every section under it, at any depth. */
    fun of(view: BinderView, asset: Asset): List<Asset> {
        val found = ArrayList<Asset>()
        val queue = mutableListOf(asset.pk)
        val seen = HashSet<Long>()
        while (queue.isNotEmpty()) {
            val row = queue.removeAt(queue.lastIndex)
            val node = view.row(Tables.assets, row)?.takeIf { seen.add(row) } ?: continue
            found += node
            queue += view.pointingAt(Tables.assets, "parent", row)
        }
        return found
    }

    /** Whether anything in [asset], or under it, isn't an example. */
    fun holdsSomethingReal(view: BinderView, asset: Asset): Boolean =
        of(view, asset).any { node -> !node.isExample || Held(view, node).holdsSomethingReal }

    /** Clears the example mark on [asset], everything under it and the people who worked on it. */
    fun makeReal(step: Step, asset: Asset) {
        for (node in of(step, asset)) {
            step.update(node.copy(isExample = false))
            val held = Held(step, node)
            held.obligations.forEach { step.update(it.copy(isExample = false)) }
            for (entry in held.history) {
                step.update(entry.copy(isExample = false))
                val items = step.all(Tables.items).filter { it.entry == entry.pk }
                items.forEach { step.update(it.copy(isExample = false)) }
            }
            held.attachments.forEach { step.update(it.copy(isExample = false)) }
            held.readings.forEach { step.update(it.copy(isExample = false)) }
            for (provider in step.linkedTo(Tables.providerAssets, node.pk)) {
                step.row(Tables.providers, provider)?.let { step.update(it.copy(isExample = false)) }
            }
        }
    }

    /** What a section holds of its own. */
    private class Held(view: BinderView, asset: Asset) {
        val obligations = view.all(Tables.obligations).filter { it.asset == asset.pk }
        val history = view.all(Tables.history).filter { it.asset == asset.pk }
        val attachments = view.all(Tables.attachments).filter { it.asset == asset.pk }
        val readings = view.all(Tables.readings).filter { it.asset == asset.pk }

        val holdsSomethingReal: Boolean
            get() = obligations.any { !it.isExample } || history.any { !it.isExample } ||
                attachments.any { !it.isExample } || readings.any { !it.isExample }
    }
}
