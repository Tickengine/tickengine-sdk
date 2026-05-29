from abc import ABC, abstractmethod

class ExecutionAgent(ABC):
    def __init__(self, name: str, symbol_map: dict):
        self.name = name
        self.symbol_map = symbol_map

    def can_handle(self, symbol: str) -> bool:
        return symbol in self.symbol_map

    @abstractmethod
    async def execute(self, event: dict, details: dict) -> None:
        pass
