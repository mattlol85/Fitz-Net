import './App.css';
import React from 'react';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import Homepage from './Homepage';
import NoPage from './NoPage';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/home" component={Homepage} > </Route>
        <Route index element={<Homepage />} />
        <Route path="*" element={<NoPage />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;