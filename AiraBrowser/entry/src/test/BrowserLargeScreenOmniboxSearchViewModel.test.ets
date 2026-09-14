import { describe, expect, it } from '@ohos/hypium';
import { ExternalAppSearchPreferences, SearchSuggestion } from '../main/ets/common/models/BrowserModels';
import {
  BrowserLargeScreenOmniboxSearchPresentationInput,
  BrowserLargeScreenOmniboxSearchViewModel
} from '../main/ets/core/browser/BrowserLargeScreenOmniboxSearchViewModel';

function createHistorySuggestion(id: string): SearchSuggestion {
  return { id: id, title: `history ${id}`, source: 'search_history', target: `q=${id}` };
}

function createRemoteSuggestion(id: string): SearchSuggestion {
  return { id: id, title: `remote ${id}`, source: 'suggestions', target: `q=${id}` };
}

function createInput(suggestions: SearchSuggestion[]): BrowserLargeScreenOmniboxSearchPresentationInput {
  const preferences: ExternalAppSearchPreferences = {
    enabled: false,
    selectedTargetIds: [],
    targetOrder: [],
    updatedAt: 0
  };
  return {
    editing: true,
    inputFocused: true,
    surfaceWidthVp: 600,
    suggestions: suggestions,
    externalAppSearchPreferences: preferences
  };
}

export default function browserLargeScreenOmniboxSearchViewModelTest(): void {
  describe('BrowserLargeScreenOmniboxSearchViewModel', () => {
    it('reports history when the list carries search history', 0, () => {
      const viewModel = new BrowserLargeScreenOmniboxSearchViewModel();

      const withHistory = viewModel.resolve(createInput([
        createHistorySuggestion('a'),
        createRemoteSuggestion('b')
      ]));

      expect(withHistory.hasHistorySuggestions).assertTrue();
      expect(withHistory.searchSuggestions.length).assertEqual(2);
    });

    it('hides the history header for remote-only suggestions', 0, () => {
      const viewModel = new BrowserLargeScreenOmniboxSearchViewModel();

      const remoteOnly = viewModel.resolve(createInput([createRemoteSuggestion('a')]));

      expect(remoteOnly.hasHistorySuggestions).assertFalse();
      expect(remoteOnly.searchSuggestions.length).assertEqual(1);
    });

    it('hides the history header when the list is empty', 0, () => {
      const viewModel = new BrowserLargeScreenOmniboxSearchViewModel();

      const empty = viewModel.resolve(createInput([]));

      expect(empty.hasHistorySuggestions).assertFalse();
      expect(empty.searchSuggestions.length).assertEqual(0);
    });

    it('stays hidden until the omnibox is editing and focused', 0, () => {
      const viewModel = new BrowserLargeScreenOmniboxSearchViewModel();
      const input = createInput([createHistorySuggestion('a')]);

      const unfocused = viewModel.resolve({
        editing: input.editing,
        inputFocused: false,
        surfaceWidthVp: input.surfaceWidthVp,
        suggestions: input.suggestions,
        externalAppSearchPreferences: input.externalAppSearchPreferences
      });

      expect(unfocused.visible).assertFalse();
    });
  });
}
